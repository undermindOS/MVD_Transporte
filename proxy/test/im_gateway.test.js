import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { STOP_INDEX_URL } from '../src/geoserver.js';
import { BUDGET_PER_MINUTE, ImGateway, STOP_META_BUCKETS } from '../src/im_gateway.js';

const TOKEN_URL =
  'https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/protocol/openid-connect/token';
const API = 'https://api.montevideo.gub.uy/api/transportepublico';

// Live answers of the official API, 2026-10-19 19:52 (-03)
const fixture = (name) =>
  readFileSync(new URL(`../contract/v1/upstream/im_api/${name}`, import.meta.url), 'utf8');
// Geoserver rows of the same four stops, 2026-10-27
const stopIndexCsv = () =>
  readFileSync(
    new URL('../contract/v1/upstream/geoserver/stop_index_sample.csv', import.meta.url),
    'utf8',
  );

const realFetch = globalThis.fetch;
const realConsoleError = console.error;
afterEach(() => {
  globalThis.fetch = realFetch;
  console.error = realConsoleError;
});

/**
 * Fake IM API: tokens on TOKEN_URL, [routes] by path under API; other
 * hosts (geoserver) by full URL. Records "METHOD url" of every call.
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
    const handler = routes[u.startsWith(API) ? u.slice(API.length) : u];
    if (!handler) return new Response('Not Found', { status: 404 });
    return handler(init);
  };
  return calls;
}

const fleet = () => new Response(fixture('im_buses.json'));
const busstops = () => new Response(fixture('im_busstops.json'));
const stopIndex = () => new Response(stopIndexCsv());

/** mockIm with what the catalog and the stop index ask for, and [routes]. */
const mockIndex = (routes = {}) =>
  mockIm({
    '/buses/busstops': busstops,
    '/buses/linevariants': () => new Response(fixture('im_linevariants.json')),
    [STOP_INDEX_URL]: stopIndex,
    ...routes,
  });

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

  it('asks once when a call starts just as the token arrives', async () => {
    const calls = mockIm({
      '/buses': fleet,
      '/buses/linevariants': () => new Response(fixture('im_linevariants.json')),
    });
    const g = gateway();
    // The second call starts the moment the token load is over
    let second;
    const forget = g.loading.delete.bind(g.loading);
    g.loading.delete = (key) => {
      const forgotten = forget(key);
      if (key === 'token') second ??= g.get_('/catalog/lines');
      return forgotten;
    };

    assert.equal((await g.get_('/lines/116/buses')).status, 200);
    assert.equal((await second).status, 200);
    assert.equal(calls.filter((c) => c.includes('token')).length, 1);
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
    mockIm({ '/buses/busstops': busstops, [STOP_INDEX_URL]: stopIndex });
    const g = gateway();

    const { stops } = await (await g.get_('/catalog/stops')).json();
    assert.deepEqual(stops[1], {
      id: 574,
      name: 'SAN JOSE y ANDES',
      location: { lat: -34.90739436, lng: -56.198255 },
      lines: ['116', '117', '121', '141', '142', '144', '538'],
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
    mockIm({
      '/buses/busstops': () => Response.json({ unexpected: true }),
      [STOP_INDEX_URL]: stopIndex,
    });
    const g = gateway();

    assert.equal((await g.get_('/catalog/stops')).status, 502);
  });
});

describe('stop index (geoserver)', () => {
  const linesById = async (response) =>
    Object.fromEntries((await response.json()).stops.map((s) => [s.id, s.lines]));

  it('joins the lines of each stop to the catalog, sorted like the app', async () => {
    const calls = mockIndex();
    const g = gateway();

    const response = await g.get_('/catalog/stops');
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('X-Lines'), null);
    const body = await response.json();
    assert.equal(body.linesAvailable, true);
    assert.deepEqual(
      Object.fromEntries(body.stops.map((s) => [s.id, s.lines])),
      {
        546: ['144'],
        574: ['116', '117', '121', '141', '142', '144', '538'],
        3140: ['140', '143', '145', '494', '495'],
        6325: ['21', '427'],
      },
    );
    assert.deepEqual(calls.sort(), [
      `GET ${API}/buses/busstops`,
      `GET ${API}/buses/linevariants`,
      `GET ${STOP_INDEX_URL}`,
      `POST ${TOKEN_URL}`,
    ]);
  });

  it('never sends the token to geoserver or spends the budget on it', async () => {
    const storage = memoryStorage();
    const headers = [];
    mockIndex({
      [STOP_INDEX_URL]: (init) => {
        headers.push(init.headers);
        return stopIndex();
      },
    });
    const g = gateway({ storage });

    await g.get_('/catalog/stops');
    assert.equal(headers.length, 1);
    assert.equal(headers[0].Authorization, undefined);
    // GET /buses/busstops and /buses/linevariants
    assert.equal((await storage.get('budget')).used, 2);
  });

  it('builds even while the key is blocked', async () => {
    const storage = memoryStorage();
    // The API answered 429 a moment ago
    await storage.put('budget', {
      minute: -1,
      used: 0,
      blockedUntil: Date.parse('2026-10-19T22:53:00Z'),
    });
    const calls = mockIndex();
    const g = gateway({ storage });

    const response = await g.get_('/catalog/stops');
    await g.settle();

    assert.equal(response.status, 503);
    assert.deepEqual(calls.sort(), [`GET ${STOP_INDEX_URL}`, `POST ${TOKEN_URL}`]);
    // Lines without directions: the line variants could not load
    assert.equal((await storage.get('stopmeta:info')).complete, false);
  });

  it(`saves the index in ${STOP_META_BUCKETS} buckets`, async () => {
    const storage = memoryStorage();
    mockIndex();
    const g = gateway({ storage });

    await g.get_('/catalog/stops');

    for (let i = 0; i < STOP_META_BUCKETS; i++) {
      assert.equal(storage.puts[`stopmeta:${i}`], 1, `stopmeta:${i}`);
    }
    assert.equal(storage.puts['stopmeta:info'], 1);
    assert.deepEqual(await storage.get('stopmeta:info'), {
      builtAt: Date.parse('2026-10-19T22:52:10Z'),
      complete: true,
    });
    // 574 % 64 = 62
    assert.deepEqual(await storage.get('stopmeta:62'), {
      byStop: {
        574: {
          lines: ['116', '117', '121', '141', '142', '144', '538'],
          directions: [{ line: '116', destination: 'POCITOS', variantIds: [630] }],
        },
      },
    });
  });

  it('a woken gateway reads the lines from storage, not from geoserver', async () => {
    const storage = memoryStorage();
    mockIndex();
    await gateway({ storage }).get_('/catalog/stops');

    const calls = mockIm({ '/buses/busstops': busstops });
    const g = gateway({ storage, start: '2026-10-20T10:00:00Z' });
    const lines = await linesById(await g.get_('/catalog/stops'));
    await g.settle();

    assert.deepEqual(lines[574], ['116', '117', '121', '141', '142', '144', '538']);
    assert.ok(!calls.some((c) => c.includes('geoserver')));
  });

  it('serves an index a day old while a new one is built', async () => {
    const storage = memoryStorage();
    mockIndex();
    const g = gateway({ storage });
    await g.get_('/catalog/stops');

    // Line 117 left stop 574
    const calls = mockIndex({
      [STOP_INDEX_URL]: () =>
        new Response('FID,cod_ubic_parada,desc_linea,cod_variante\r\nf,574,116,630\r\n'),
    });
    g.tick(25 * 3600 * 1000);
    const old = await linesById(await g.get_('/catalog/stops'));
    await g.settle();
    const fresh = await linesById(await g.get_('/catalog/stops'));

    assert.deepEqual(old[574], ['116', '117', '121', '141', '142', '144', '538']);
    assert.deepEqual(fresh[574], ['116']);
    assert.deepEqual(fresh[546], []);
    assert.equal(calls.filter((c) => c.includes('geoserver')).length, 1);
    assert.equal((await storage.get('stopmeta:info')).builtAt, Date.parse('2026-10-20T23:52:10Z'));
  });

  it('drops an index older than 7 days', async () => {
    const logs = [];
    console.error = (...args) => logs.push(args.join(' '));
    const storage = memoryStorage();
    mockIndex();
    await gateway({ storage }).get_('/catalog/stops');

    mockIndex({ [STOP_INDEX_URL]: () => new Response('', { status: 500 }) });
    const g = gateway({ storage, start: '2026-10-26T22:52:10Z' });
    const response = await g.get_('/catalog/stops');
    await g.settle();

    assert.equal(response.headers.get('X-Lines'), '0');
    assert.equal((await response.json()).linesAvailable, false);
    assert.deepEqual(logs, ['geoserver: HTTP 500']);
  });

  it('builds once for concurrent requests', async () => {
    const calls = mockIndex();
    const g = gateway();

    const answers = await Promise.all(Array.from({ length: 10 }, () => g.get_('/catalog/stops')));

    for (const response of answers) {
      assert.equal((await response.json()).linesAvailable, true);
    }
    assert.equal(calls.filter((c) => c.includes('geoserver')).length, 1);
  });

  it('answers without lines when geoserver fails, and tries again after 15 min', async () => {
    const logs = [];
    console.error = (...args) => logs.push(args.join(' '));
    const calls = mockIndex({ [STOP_INDEX_URL]: () => new Response('', { status: 500 }) });
    const g = gateway();

    const response = await g.get_('/catalog/stops');
    await g.settle();
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('X-Lines'), '0');
    const body = await response.json();
    assert.equal(body.linesAvailable, false);
    assert.equal(body.stops.length, 4);
    assert.ok(body.stops.every((s) => s.lines.length === 0));
    // Line variants are not asked for without the CSV
    assert.ok(!calls.some((c) => c.endsWith('/linevariants')));
    assert.deepEqual(logs, ['geoserver: HTTP 500']);

    g.tick(14 * 60 * 1000);
    await g.get_('/catalog/stops');
    await g.settle();
    assert.equal(calls.filter((c) => c.includes('geoserver')).length, 1);

    mockIndex();
    g.tick(60 * 1000);
    const again = await g.get_('/catalog/stops');
    assert.equal(again.headers.get('X-Lines'), null);
    assert.equal((await again.json()).linesAvailable, true);
  });
});

describe('GET /stops/{id}/meta', () => {
  it('answers 503 until the index is built, then the lines and where they go', async () => {
    const calls = mockIndex();
    const g = gateway();

    const first = await g.get_('/stops/574/meta');
    assert.equal(first.status, 503);
    assert.equal(first.headers.get('Retry-After'), '30');
    assert.deepEqual(await first.json(), { error: 'upstream_busy' });
    await g.settle();

    const response = await g.get_('/stops/574/meta');
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), {
      builtAt: '2026-10-19T22:52:10.000Z',
      complete: true,
      lines: ['116', '117', '121', '141', '142', '144', '538'],
      // Of the stop's 15 variants only 630 is in the line variants sample
      directions: [{ line: '116', destination: 'POCITOS', variantIds: [630] }],
    });
    assert.deepEqual(calls.sort(), [
      `GET ${API}/buses/linevariants`,
      `GET ${STOP_INDEX_URL}`,
      `POST ${TOKEN_URL}`,
    ]);
  });

  it('spends one unit of budget, for the line variants, none for geoserver', async () => {
    const storage = memoryStorage();
    const budgetAtGeoserver = [];
    mockIndex({
      [STOP_INDEX_URL]: async () => {
        budgetAtGeoserver.push(await storage.get('budget'));
        return stopIndex();
      },
    });
    const g = gateway({ storage });

    await g.get_('/stops/574/meta');
    await g.settle();

    assert.deepEqual(budgetAtGeoserver, [undefined]);
    assert.equal((await storage.get('budget')).used, 1);
  });

  it('answers empty lists for a stop the index does not have', async () => {
    mockIndex();
    const g = gateway();
    await g.get_('/stops/574/meta');
    await g.settle();

    assert.deepEqual(await (await g.get_('/stops/9999999/meta')).json(), {
      builtAt: '2026-10-19T22:52:10.000Z',
      complete: true,
      lines: [],
      directions: [],
    });
  });

  it('gives one direction per line and destination, sorted like the app', async () => {
    const variant = (lineVariantId, line, destination, special = false) => ({
      lineVariantId,
      line,
      destination,
      special,
    });
    mockIndex({
      [STOP_INDEX_URL]: () =>
        new Response(
          [
            'FID,cod_ubic_parada,desc_linea,cod_variante',
            ...[2, 1, 3, 4, 5, 6, 7, 8, 9, 10].map((v) => `f${v},100,x,${v}`),
          ].join('\r\n'),
        ),
      '/buses/linevariants': () =>
        Response.json([
          variant(1, '21', 'ÁLVAREZ'),
          variant(2, '21', 'ÁLVAREZ'),
          variant(3, '21', 'BELVEDERE'),
          variant(4, '124 SD', 'CENTRO'),
          variant(5, 'D10', 'PUNTA CARRETAS'),
          variant(6, 'D9', 'PUNTA CARRETAS'),
          variant(8, '21', ''),
          variant(9, '121', 'ZOOLÓGICO', true),
          variant(10, '21', 'ÁLVAREZ'),
          // 7 is not in the official API
        ]),
    });
    const g = gateway();
    await g.get_('/stops/100/meta');
    await g.settle();

    const { directions } = await (await g.get_('/stops/100/meta')).json();
    assert.deepEqual(directions, [
      // "B" (U+0042) before "Á" (U+00C1): code units, not the dictionary
      { line: '21', destination: 'BELVEDERE', variantIds: [3] },
      { line: '21', destination: 'ÁLVAREZ', variantIds: [1, 2, 10] },
      // A special variant is still a direction
      { line: '121', destination: 'ZOOLÓGICO', variantIds: [9] },
      { line: '124 SD', destination: 'CENTRO', variantIds: [4] },
      { line: 'D10', destination: 'PUNTA CARRETAS', variantIds: [5] },
      { line: 'D9', destination: 'PUNTA CARRETAS', variantIds: [6] },
    ]);
  });

  it('keeps the lines but no directions when the line variants fail, and tries again after 15 min', async () => {
    const logs = [];
    console.error = (...args) => logs.push(args.join(' '));
    const storage = memoryStorage();
    mockIndex({ '/buses/linevariants': () => new Response('', { status: 500 }) });
    const g = gateway({ storage });
    await g.get_('/stops/574/meta');
    await g.settle();

    const incomplete = await (await g.get_('/stops/574/meta')).json();
    assert.equal(incomplete.complete, false);
    assert.deepEqual(incomplete.lines, ['116', '117', '121', '141', '142', '144', '538']);
    assert.deepEqual(incomplete.directions, []);
    assert.equal((await storage.get('stopmeta:info')).complete, false);
    assert.deepEqual(logs, ['im-gateway: no line variants']);

    const calls = mockIndex();
    g.tick(15 * 60 * 1000);
    // Served as it is while a new build runs
    assert.equal((await (await g.get_('/stops/574/meta')).json()).complete, false);
    await g.settle();

    const complete = await (await g.get_('/stops/574/meta')).json();
    assert.equal(complete.complete, true);
    assert.deepEqual(complete.directions, [
      { line: '116', destination: 'POCITOS', variantIds: [630] },
    ]);
    assert.equal(calls.filter((c) => c.endsWith('/linevariants')).length, 1);
  });

  it('a woken gateway answers from storage without any request', async () => {
    const storage = memoryStorage();
    mockIndex();
    const first = gateway({ storage });
    await first.get_('/stops/574/meta');
    await first.settle();

    const calls = mockIm({});
    const g = gateway({ storage, start: '2026-10-20T10:00:00Z' });
    const response = await g.get_('/stops/574/meta');
    await g.settle();

    assert.equal(response.status, 200);
    assert.deepEqual((await response.json()).directions, [
      { line: '116', destination: 'POCITOS', variantIds: [630] },
    ]);
    assert.deepEqual(calls, []);
  });

  it('a woken gateway still waits 15 min after a failed build', async () => {
    const logs = [];
    console.error = (...args) => logs.push(args.join(' '));
    const storage = memoryStorage();
    const calls = mockIndex({ [STOP_INDEX_URL]: () => new Response('', { status: 500 }) });
    const first = gateway({ storage });
    await first.get_('/stops/574/meta');
    await first.settle();

    const woken = gateway({ storage, start: '2026-10-19T22:54:10Z' });
    assert.equal((await woken.get_('/stops/574/meta')).status, 503);
    await woken.settle();
    assert.equal(calls.filter((c) => c.includes('geoserver')).length, 1);
    assert.deepEqual(logs, ['geoserver: HTTP 500']);

    const later = mockIndex();
    const g = gateway({ storage, start: '2026-10-19T23:07:10Z' });
    await g.get_('/stops/574/meta');
    await g.settle();
    assert.equal(later.filter((c) => c.includes('geoserver')).length, 1);
    assert.equal((await g.get_('/stops/574/meta')).status, 200);
  });

  it('drops copies older than 7 days', async () => {
    const storage = memoryStorage();
    mockIndex();
    const first = gateway({ storage });
    await first.get_('/stops/574/meta');
    await first.settle();

    const calls = mockIndex();
    const g = gateway({ storage, start: '2026-10-26T22:52:10Z' });
    const response = await g.get_('/stops/574/meta');
    await g.settle();

    assert.equal(response.status, 503);
    assert.equal(calls.filter((c) => c.includes('geoserver')).length, 1);
    assert.equal(
      (await storage.get('stopmeta:info')).builtAt,
      Date.parse('2026-10-26T22:52:10Z'),
    );
  });
});
