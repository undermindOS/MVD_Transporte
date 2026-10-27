import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { BUDGET_PER_MINUTE, ImGateway } from '../src/im_gateway.js';

const TOKEN_URL =
  'https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/protocol/openid-connect/token';
const API = 'https://api.montevideo.gub.uy/api/transportepublico';

// Live answers of the official API, 2026-10-19 19:52 (-03)
const fixture = (name) =>
  readFileSync(new URL(`../contract/v1/upstream/im_api/${name}`, import.meta.url), 'utf8');

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/**
 * Fake IM API: tokens on TOKEN_URL, [routes] by path under API.
 * Records "METHOD url" of every call.
 */
function mockIm(routes = {}) {
  const calls = [];
  let tokens = 0;
  globalThis.fetch = async (url, init = {}) => {
    const u = String(url);
    calls.push(`${init.method ?? 'GET'} ${u}`);
    if (u === TOKEN_URL) {
      tokens++;
      return Response.json({ access_token: `token-${tokens}`, expires_in: 300 });
    }
    const handler = routes[u.slice(API.length)];
    if (!handler) return new Response('Not Found', { status: 404 });
    return handler(init);
  };
  return calls;
}

const fleet = () => new Response(fixture('im_buses.json'));

/** Durable Object storage in memory; survives a "restarted" gateway. */
function memoryStorage() {
  const values = new Map();
  return {
    puts: {}, // key → number of writes
    async get(key) {
      return structuredClone(values.get(key));
    },
    async put(key, value) {
      this.puts[key] = (this.puts[key] ?? 0) + 1;
      values.set(key, structuredClone(value));
    },
  };
}

/** Gateway with a clock the test moves. */
function gateway({
  env = { IM_CLIENT_ID: 'id', IM_CLIENT_SECRET: 'secret' },
  storage,
  start = '2026-10-19T22:52:10Z',
} = {}) {
  const pending = [];
  const g = new ImGateway({ waitUntil: (p) => pending.push(p), storage }, env);
  let now = Date.parse(start);
  g.now = () => now;
  g.tick = (ms) => {
    now += ms;
  };
  g.settle = () => Promise.all(pending.splice(0));
  g.get_ = (path) => g.fetch(new Request(`https://im-gateway${path}`));
  return g;
}

describe('GET /vehicles', () => {
  it('returns comfort of the asked buses from one fleet snapshot', async () => {
    const calls = mockIm({ '/buses': fleet });
    const g = gateway();

    const response = await g.get_('/vehicles?ids=50:111,50:139,50:918,70:52,50:999999');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      fetchedAt: '2026-10-19T22:52:10.000Z',
      vehicles: {
        // Aire Acondicionado, Euro V
        '50:111': { airConditioning: true, zeroEmission: false },
        // Cero emisiones
        '50:139': { airConditioning: true, zeroEmission: true },
        // Sin datos, Euro III
        '50:918': { airConditioning: null, zeroEmission: false },
        // Sin datos, Sin datos
        '70:52': { airConditioning: null, zeroEmission: null },
      },
    });
    assert.deepEqual(calls, [`POST ${TOKEN_URL}`, `GET ${API}/buses`]);
  });

  it('sends the bearer token and reuses it until it expires', async () => {
    const auth = [];
    mockIm({
      '/buses': (init) => {
        auth.push(init.headers.Authorization);
        return fleet();
      },
    });
    const g = gateway();

    await g.get_('/vehicles?ids=50:111');
    g.tick(20 * 1000); // past the fleet TTL: a background refresh
    await g.get_('/vehicles?ids=50:111');
    await g.settle();
    g.tick(5 * 60 * 1000); // past the token lifetime
    await g.get_('/vehicles?ids=50:111');
    await g.settle();

    assert.deepEqual(auth, ['Bearer token-1', 'Bearer token-1', 'Bearer token-2']);
  });

  it('loads the fleet once for concurrent requests', async () => {
    const calls = mockIm({ '/buses': fleet });
    const g = gateway();

    const answers = await Promise.all(
      Array.from({ length: 20 }, () => g.get_('/vehicles?ids=50:111')),
    );

    assert.ok(answers.every((r) => r.status === 200));
    assert.equal(calls.filter((c) => c.endsWith('/buses')).length, 1);
    assert.equal(calls.filter((c) => c.includes('token')).length, 1);
  });

  it('answers from the old snapshot while a new one loads', async () => {
    let release;
    mockIm({ '/buses': fleet });
    const g = gateway();
    await g.get_('/vehicles?ids=50:111');

    // The next GET /buses hangs until released: awaiting it would time out
    const calls = mockIm({
      '/buses': () =>
        new Promise((resolve) => {
          release = () => resolve(new Response('[]'));
        }),
    });
    g.tick(16 * 1000);
    const response = await g.get_('/vehicles?ids=50:111');
    const body = await response.json();

    assert.equal(body.fetchedAt, '2026-10-19T22:52:10.000Z');
    assert.ok(body.vehicles['50:111']);
    assert.deepEqual(calls, [`GET ${API}/buses`]); // the refresh has started
    release();
    await g.settle();
  });

  it('keeps the old snapshot when a background refresh fails', async () => {
    mockIm({ '/buses': fleet });
    const g = gateway();
    await g.get_('/vehicles?ids=50:111');

    mockIm({ '/buses': () => new Response('boom', { status: 500 }) });
    g.tick(16 * 1000);
    await g.get_('/vehicles?ids=50:111');
    await g.settle();

    const body = await (await g.get_('/vehicles?ids=50:111')).json();
    assert.ok(body.vehicles['50:111']);
  });
});

describe('comfort kept across evictions', () => {
  it('a restarted gateway answers from storage without waiting for GET /buses', async () => {
    const storage = memoryStorage();
    mockIm({ '/buses': fleet });
    await gateway({ storage }).get_('/vehicles?ids=50:111');

    // Evicted on idle; the next GET /buses hangs: awaiting it would time out
    let release;
    let asked;
    const refreshStarted = new Promise((resolve) => {
      asked = resolve;
    });
    mockIm({
      '/buses': () => {
        asked();
        return new Promise((resolve) => {
          release = () => resolve(fleet());
        });
      },
    });
    const g = gateway({ storage, start: '2026-10-19T23:30:00Z' });
    const body = await (await g.get_('/vehicles?ids=50:111,50:139')).json();

    assert.deepEqual(body, {
      fetchedAt: '2026-10-19T22:52:10.000Z',
      vehicles: {
        '50:111': { airConditioning: true, zeroEmission: false },
        '50:139': { airConditioning: true, zeroEmission: true },
      },
    });
    // The fresh snapshot is on its way (never asked → the test times out)
    await refreshStarted;
    release();
    await g.settle();
  });

  it('saves to storage at most every 5 minutes', async () => {
    const storage = memoryStorage();
    mockIm({ '/buses': fleet });
    const g = gateway({ storage });

    for (let i = 0; i < 20; i++) {
      await g.get_('/vehicles?ids=50:111'); // a background load every 16 s
      await g.settle();
      g.tick(16 * 1000);
    }

    // 20 loads over 5 min 20 s
    assert.equal(storage.puts.comfort, 2);
    assert.equal(storage.puts.budget, 20);
  });

  it('remembers buses that are not in the latest snapshot', async () => {
    mockIm({ '/buses': fleet });
    const g = gateway();
    await g.get_('/vehicles?ids=50:111');

    // Bus 111 ended its shift
    mockIm({ '/buses': () => Response.json([]) });
    g.tick(16 * 1000);
    await g.get_('/vehicles?ids=50:111');
    await g.settle();

    const body = await (await g.get_('/vehicles?ids=50:111')).json();
    assert.equal(body.fetchedAt, '2026-10-19T22:52:26.000Z');
    assert.deepEqual(body.vehicles, {
      '50:111': { airConditioning: true, zeroEmission: false },
    });
  });

  it('loads the fleet when the stored comfort is a day old', async () => {
    const storage = memoryStorage();
    mockIm({ '/buses': fleet });
    await gateway({ storage }).get_('/vehicles?ids=50:111');

    mockIm({ '/buses': () => Response.json([]) });
    const g = gateway({ storage, start: '2026-10-20T22:52:10Z' });
    const body = await (await g.get_('/vehicles?ids=50:111')).json();

    // Waited for the new snapshot; old entries are still known
    assert.equal(body.fetchedAt, '2026-10-20T22:52:10.000Z');
    assert.ok(body.vehicles['50:111']);
  });
});

describe('request budget', () => {
  it(`never spends more than ${BUDGET_PER_MINUTE} requests a minute`, async () => {
    const calls = mockIm({ '/buses': fleet });
    const g = gateway();

    // Without a usable copy every request has to load the fleet
    const statuses = [];
    for (let i = 0; i < BUDGET_PER_MINUTE + 3; i++) {
      g.copies.clear();
      statuses.push((await g.get_('/lines/116/buses')).status);
    }

    assert.equal(calls.filter((c) => c.endsWith('/buses')).length, BUDGET_PER_MINUTE);
    assert.deepEqual(statuses.slice(-3), [503, 503, 503]);
    const busy = await (g.copies.clear(), g.get_('/lines/116/buses'));
    assert.deepEqual(await busy.json(), { error: 'upstream_busy' });
    // 22:52:10 → the window resets at 22:53:00
    assert.equal(busy.headers.get('Retry-After'), '50');

    g.tick(50 * 1000);
    g.copies.clear();
    assert.equal((await g.get_('/lines/116/buses')).status, 200);
  });

  it('keeps counting after the object wakes up from hibernation', async () => {
    const storage = memoryStorage();
    const calls = mockIm({ '/buses': fleet });
    const first = gateway({ storage });
    for (let i = 0; i < BUDGET_PER_MINUTE; i++) {
      first.copies.clear();
      await first.get_('/lines/116/buses');
    }

    // Same minute, new instance with empty memory
    const woken = gateway({ storage, start: '2026-10-19T22:52:40Z' });
    const response = await woken.get_('/lines/116/buses');

    assert.equal(response.status, 503);
    assert.equal(response.headers.get('Retry-After'), '20');
    assert.equal(calls.filter((c) => c.endsWith('/buses')).length, BUDGET_PER_MINUTE);
  });

  it('waits as long as the API says after a 429', async () => {
    const calls = mockIm({
      '/buses': () =>
        new Response('Usage limit exceeded', {
          status: 429,
          headers: { 'Retry-After': '11' },
        }),
    });
    const g = gateway();

    const first = await g.get_('/lines/116/buses');
    assert.equal(first.status, 503);
    assert.equal(first.headers.get('Retry-After'), '11');

    g.tick(5 * 1000);
    const second = await g.get_('/lines/116/buses');
    assert.equal(second.headers.get('Retry-After'), '6');
    assert.equal(calls.filter((c) => c.endsWith('/buses')).length, 1);
  });
});

describe('token', () => {
  it('gets a new token once when the API refuses the old one', async () => {
    let refused = false;
    const calls = mockIm({
      '/buses': (init) => {
        if (!refused) {
          refused = true;
          return new Response('', { status: 401 });
        }
        assert.equal(init.headers.Authorization, 'Bearer token-2');
        return fleet();
      },
    });
    const g = gateway();

    assert.equal((await g.get_('/lines/116/buses')).status, 200);
    assert.equal(calls.filter((c) => c.includes('token')).length, 2);
  });

  it('answers 502 when the client secret is refused', async () => {
    globalThis.fetch = async () =>
      Response.json({ error: 'unauthorized_client' }, { status: 401 });
    const g = gateway();

    const response = await g.get_('/lines/116/buses');
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: 'upstream_error' });
  });

  it('answers 503 not_configured without secrets', async () => {
    const calls = mockIm({ '/buses': fleet });
    const g = gateway({ env: {} });

    const response = await g.get_('/vehicles?ids=50:111');
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'not_configured' });
    assert.deepEqual(calls, []);
  });
});

describe('GET /lines/{line}/buses', () => {
  it('lists the live buses of a line', async () => {
    mockIm({ '/buses': fleet });
    const g = gateway();

    const { buses } = await (await g.get_('/lines/117/buses')).json();
    assert.deepEqual(buses, [
      {
        companyId: 50,
        busId: 111,
        variantId: 2779,
        destination: 'PUNTA CARRETAS',
        location: { lat: -34.909443, lng: -56.207848 },
        speedKmh: 21,
        updatedAt: '2026-10-19T22:51:57.000Z',
        airConditioning: true,
        zeroEmission: false,
      },
    ]);
  });

  it('maps every operator to its transporteRest id', async () => {
    mockIm({ '/buses': fleet });
    const g = gateway();

    const ids = async (line) =>
      (await (await g.get_(`/lines/${line}/buses`)).json()).buses.map((b) => b.companyId);
    assert.deepEqual(await ids('405'), [10]); // COETC
    assert.deepEqual(await ids('524'), [20]); // COME
    assert.deepEqual(await ids('116'), [50]); // CUTCSA
    assert.deepEqual(await ids('328'), [70]); // UCOT
  });
});

describe('catalogs', () => {
  it('maps stops with names like transporteRest', async () => {
    mockIm({ '/buses/busstops': () => new Response(fixture('im_busstops.json')) });
    const g = gateway();

    const { stops } = await (await g.get_('/catalog/stops')).json();
    assert.deepEqual(stops[1], {
      id: 574,
      name: 'SAN JOSE y ANDES',
      location: { lat: -34.90739436, lng: -56.198255 },
    });
    // A stop with one street only
    assert.equal(stops[3].name, 'MATAOJO');
  });

  it('maps line variants and keeps them for a day', async () => {
    const calls = mockIm({
      '/buses/linevariants': () => new Response(fixture('im_linevariants.json')),
    });
    const g = gateway();

    const { variants } = await (await g.get_('/catalog/lines')).json();
    assert.deepEqual(variants[1], {
      id: 11,
      line: '402',
      origin: 'PLAYA MALVÍN',
      destination: '8 DE OCTUBRE Y COMERCIO',
      subline: 'CIUDAD VIEJA - MALVIN',
      special: true,
    });

    g.tick(23 * 3600 * 1000);
    await g.get_('/catalog/lines');
    assert.equal(calls.filter((c) => c.endsWith('/linevariants')).length, 1);
  });

  it('answers 502 on JSON of the wrong shape', async () => {
    mockIm({ '/buses/busstops': () => Response.json({ unexpected: true }) });
    const g = gateway();

    assert.equal((await g.get_('/catalog/stops')).status, 502);
  });
});
