import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import worker from '../src/index.js';

const UPSTREAM = 'https://api.montevideo.gub.uy/transporteRest';

// Live transporteRest answers, 2026-10-19
const fixture = (name) =>
  readFileSync(new URL(`fixtures/${name}`, import.meta.url), 'utf8');
const NOT_FOUND_BODY = "No existe la ubicación de parada con código '99999999'.";

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Replies to upstream calls with [handler(url)] and records the URLs. */
function mockUpstream(handler) {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return handler(String(url));
  };
  return calls;
}

function call(path, { method = 'GET', allowed = true, ip = '203.0.113.7' } = {}) {
  const keys = [];
  const env = {
    IP_LIMITER: {
      limit: async ({ key }) => {
        keys.push(key);
        return { success: allowed };
      },
    },
  };
  const request = new Request(`https://proxy.test${path}`, {
    method,
    headers: { 'CF-Connecting-IP': ip },
  });
  return worker.fetch(request, env).then((response) => ({ response, keys }));
}

describe('GET /v1/stops/{id}', () => {
  it('returns name and lines, cached for a day', async () => {
    const calls = mockUpstream(() => new Response(fixture('lineas_574.json')));
    const { response } = await call('/v1/stops/574');

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=86400');
    assert.deepEqual(await response.json(), {
      id: 574,
      name: 'SAN JOSE y ANDES',
      lines: ['116', '117', '121', '141', '142', '144', '538'],
    });
    assert.deepEqual(calls, [`${UPSTREAM}/lineas/574`]);
  });

  it('answers 404 stop_not_found for an unknown stop, cached for an hour', async () => {
    mockUpstream(() => new Response(NOT_FOUND_BODY, { status: 500 }));
    const { response } = await call('/v1/stops/99999');

    assert.equal(response.status, 404);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=3600');
    assert.deepEqual(await response.json(), { error: 'stop_not_found' });
  });
});

describe('GET /v1/stops/{id}/arrivals', () => {
  it('maps arrivals soonest first, cached for 15 s', async () => {
    const calls = mockUpstream(() => new Response(fixture('arrivals_3140.json')));
    const { response } = await call('/v1/stops/3140/arrivals');

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=15');
    assert.deepEqual(calls, [`${UPSTREAM}/siguientesParada/3140`]);

    const body = await response.json();
    assert.ok(!Number.isNaN(Date.parse(body.fetchedAt)));
    assert.deepEqual(
      body.arrivals.map((a) => [a.line, a.etaMinutes]),
      [['494', 8], ['145', 10], ['143', 11], ['140', 40], ['495', 262]],
    );
    assert.deepEqual(body.arrivals[0], {
      line: '494',
      destination: 'DELTA DEL TIGRE',
      etaMinutes: 8,
      realTime: true,
      scheduledTime: '19:06',
      companyId: 10,
      location: { lat: -34.897755, lng: -56.12432 },
      accessible: false,
      accessibilityType: 1,
    });
    // Timetable-only bus: no GPS position, no operator
    assert.equal(body.arrivals[2].realTime, false);
    assert.equal(body.arrivals[2].location, null);
    assert.equal(body.arrivals[2].companyId, null);
  });

  it('skips items without line or minutes', async () => {
    mockUpstream(() =>
      Response.json([
        { linea: '', minutos: 3 },
        { linea: '145', minutos: null },
        { linea: 'G8', minutos: '4' },
        'garbage',
      ]),
    );
    const { response } = await call('/v1/stops/3140/arrivals');
    const { arrivals } = await response.json();

    assert.deepEqual(arrivals.map((a) => [a.line, a.etaMinutes]), [['G8', 4]]);
  });
});

describe('GET /v1/stops/{id}/schedule/{day}/{H:MM}', () => {
  it('maps the timetable for the day type, cached for 6 h', async () => {
    const calls = mockUpstream(() =>
      new Response(fixture('schedule_3140_habil_805.json')),
    );
    const { response } = await call('/v1/stops/3140/schedule/weekday/8:05');

    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=21600');
    assert.deepEqual(calls, [`${UPSTREAM}/siguientesParada/3140/HABIL/8:05`]);

    const { passes } = await response.json();
    assert.equal(passes.length, 50);
    assert.deepEqual(passes[0], {
      line: '143',
      destination: 'CIUDADELA',
      time: '8:09',
      hhmm: 809,
    });
  });

  it('maps saturday and sunday and pads minutes', async () => {
    const calls = mockUpstream(() => Response.json([]));
    await call('/v1/stops/3140/schedule/saturday/23:00');
    await call('/v1/stops/3140/schedule/sunday/07:30');

    assert.deepEqual(calls, [
      `${UPSTREAM}/siguientesParada/3140/SABADO/23:00`,
      `${UPSTREAM}/siguientesParada/3140/DOMINGO/7:30`,
    ]);
  });
});

describe('upstream failures', () => {
  it('answers 502 on another upstream error, not cached', async () => {
    // What the backend answers to an unknown day type: mentions
    // NoExisteTransporteException but is not "stop not found"
    mockUpstream(
      () =>
        new Response('{ "tipo": "BadRequestException", "mensaje": "... NoExisteTransporteException" }', {
          status: 500,
        }),
    );
    const { response } = await call('/v1/stops/3140/arrivals');

    assert.equal(response.status, 502);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.deepEqual(await response.json(), { error: 'upstream_error' });
  });

  it('answers 502 on a body that is not JSON', async () => {
    mockUpstream(() => new Response('<html>maintenance</html>'));
    const { response } = await call('/v1/stops/574');

    assert.equal(response.status, 502);
  });

  it('answers 502 on JSON of the wrong shape', async () => {
    mockUpstream(() => Response.json({ unexpected: true }));
    const { response } = await call('/v1/stops/3140/arrivals');

    assert.equal(response.status, 502);
  });

  it('answers 504 on timeout', async () => {
    mockUpstream(() => {
      throw new DOMException('The operation timed out.', 'TimeoutError');
    });
    const { response } = await call('/v1/stops/3140/arrivals');

    assert.equal(response.status, 504);
    assert.deepEqual(await response.json(), { error: 'upstream_timeout' });
  });
});

describe('requests that never reach transporteRest', () => {
  const cases = [
    ['/', 404, 'not_found'],
    ['/v1/stops', 404, 'not_found'],
    ['/v1/stops/abc', 404, 'not_found'],
    ['/v1/stops/0574', 404, 'not_found'],
    ['/v1/stops/12345678', 404, 'not_found'],
    ['/v1/stops/574/', 404, 'not_found'],
    ['/v1/stops/574?nocache=1', 400, 'bad_request'],
    ['/v1/stops/3140/schedule/holiday/8:05', 400, 'bad_request'],
    ['/v1/stops/3140/schedule/constructor/8:05', 400, 'bad_request'],
    ['/v1/stops/3140/schedule/weekday/24:00', 400, 'bad_request'],
    ['/v1/stops/3140/schedule/weekday/8:60', 400, 'bad_request'],
    ['/v1/stops/3140/schedule/weekday/805', 404, 'not_found'],
  ];

  for (const [path, status, code] of cases) {
    it(`${path} → ${status}`, async () => {
      const calls = mockUpstream(() => assert.fail('upstream called'));
      const { response } = await call(path);

      assert.equal(response.status, status);
      assert.equal(response.headers.get('Cache-Control'), 'no-store');
      assert.deepEqual(await response.json(), { error: code });
      assert.deepEqual(calls, []);
    });
  }

  it('POST → 405', async () => {
    const calls = mockUpstream(() => assert.fail('upstream called'));
    const { response } = await call('/v1/stops/574', { method: 'POST' });

    assert.equal(response.status, 405);
    assert.equal(response.headers.get('Allow'), 'GET');
    assert.deepEqual(calls, []);
  });
});

describe('IP limit', () => {
  it('counts every request by client IP', async () => {
    mockUpstream(() => new Response(fixture('lineas_574.json')));
    const { keys } = await call('/v1/stops/574', { ip: '198.51.100.20' });

    assert.deepEqual(keys, ['198.51.100.20']);
  });

  it('answers 429 over the limit without calling transporteRest', async () => {
    const calls = mockUpstream(() => assert.fail('upstream called'));
    const { response } = await call('/v1/stops/3140/arrivals', { allowed: false });

    assert.equal(response.status, 429);
    assert.equal(response.headers.get('Retry-After'), '60');
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.deepEqual(await response.json(), { error: 'rate_limited' });
    assert.deepEqual(calls, []);
  });
});
