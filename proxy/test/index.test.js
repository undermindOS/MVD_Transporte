import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import worker, { ImGateway, respond } from '../src/index.js';

const UPSTREAM = 'https://api.montevideo.gub.uy/transporteRest';

// Live upstream answers, 2026-10-19, shared with the app (../contract/v1)
const fixture = (name) =>
  readFileSync(new URL(`../contract/v1/upstream/${name}`, import.meta.url), 'utf8');
const NOT_FOUND_BODY = "No existe la ubicación de parada con código '99999999'.";

const realFetch = globalThis.fetch;
const realConsoleError = console.error;
afterEach(() => {
  globalThis.fetch = realFetch;
  console.error = realConsoleError;
});

/** Records what is logged with console.error from now on. */
function captureLogs() {
  const lines = [];
  console.error = (...args) => lines.push(args.join(' '));
  return lines;
}

/** Replies to upstream calls with [handler(url)] and records the URLs. */
function mockUpstream(handler) {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return handler(String(url));
  };
  return calls;
}

/** Durable Object namespace whose only object answers with [handler(url)]. */
function gatewayNamespace(handler) {
  const paths = [];
  return {
    paths,
    idFromName: (name) => {
      assert.equal(name, 'global');
      return name;
    },
    get: () => ({
      fetch: async (url) => {
        paths.push(String(url).replace('https://im-gateway', ''));
        return handler(String(url));
      },
    }),
  };
}

function call(
  path,
  { method = 'GET', allowed = true, ip = '203.0.113.7', gateway } = {},
) {
  const keys = [];
  const env = {
    IP_LIMITER: {
      limit: async ({ key }) => {
        keys.push(key);
        return { success: allowed };
      },
    },
    ...(gateway && { IM_GATEWAY: gateway }),
  };
  const request = new Request(`https://proxy.test${path}`, {
    method,
    headers: { 'CF-Connecting-IP': ip },
  });
  return worker.fetch(request, env).then((response) => ({ response, keys }));
}

describe('GET /v1/stops/{id}', () => {
  it('returns name and lines, cached for a day', async () => {
    const calls = mockUpstream(() => new Response(fixture('transporte_rest/lineas_574.json')));
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
    const calls = mockUpstream(() => new Response(fixture('transporte_rest/arrivals_3140.json')));
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
      // No ImGateway in this env: comfort is unknown, arrivals still work
      vehicle: null,
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

describe('GET /v1/stops/{id}/arrivals with comfort from the official API', () => {
  // transporteRest and the official API answered at the same minute
  const IM = 'https://api.montevideo.gub.uy/api/transportepublico';
  function mockBoth() {
    const calls = mockUpstream((url) => {
      if (url.startsWith(UPSTREAM)) {
        return new Response(fixture('transporte_rest/arrivals_574.json'));
      }
      if (url.includes('openid-connect/token')) {
        return Response.json({ access_token: 't', expires_in: 300 });
      }
      if (url === `${IM}/buses`) return new Response(fixture('im_api/im_buses.json'));
      return assert.fail(`unexpected ${url}`);
    });
    return calls;
  }

  it('adds air conditioning and zero emission to GPS buses', async () => {
    const calls = mockBoth();
    const im = new ImGateway({}, { IM_CLIENT_ID: 'id', IM_CLIENT_SECRET: 's' });
    const gateway = gatewayNamespace((url) => im.fetch(new Request(url)));

    const { response } = await call('/v1/stops/574/arrivals', { gateway });
    assert.equal(response.status, 200);
    const { arrivals } = await response.json();

    const byLine = Object.fromEntries(arrivals.map((a) => [a.line, a.vehicle]));
    assert.deepEqual(byLine, {
      117: { airConditioning: true, zeroEmission: false }, // bus 111, Euro V
      121: { airConditioning: true, zeroEmission: false }, // bus 1118
      116: { airConditioning: true, zeroEmission: true }, // bus 139, eléctrico
      // Timetable only: no bus to look up
      144: null,
      538: null,
      142: null,
    });
    // The internal id used for the match is not part of the contract
    assert.ok(arrivals.every((a) => !('busId' in a)));
    assert.deepEqual(
      gateway.paths.map((p) => p.split('=')[1].split(',').sort()),
      [['50:111', '50:1118', '50:139']],
    );
    assert.equal(calls.filter((c) => c === `${IM}/buses`).length, 1);
  });

  it('serves arrivals without comfort when the gateway is busy', async () => {
    mockUpstream(() => new Response(fixture('transporte_rest/arrivals_574.json')));
    const gateway = gatewayNamespace(() =>
      Response.json({ error: 'upstream_busy' }, { status: 503 }),
    );

    const { response } = await call('/v1/stops/574/arrivals', { gateway });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=15');
    const { arrivals } = await response.json();
    assert.ok(arrivals.every((a) => a.vehicle === null));
  });

  it('serves arrivals without comfort when the gateway throws', async () => {
    mockUpstream(() => new Response(fixture('transporte_rest/arrivals_574.json')));
    const gateway = gatewayNamespace(() => {
      throw new Error('Durable Object overloaded');
    });

    const { response } = await call('/v1/stops/574/arrivals', { gateway });
    assert.equal(response.status, 200);
  });

  it('does not wait more than 2 s for comfort', async () => {
    mockUpstream(() => new Response(fixture('transporte_rest/arrivals_574.json')));
    const gateway = gatewayNamespace(() => new Promise(() => {}));

    const started = Date.now();
    const { response } = await call('/v1/stops/574/arrivals', { gateway });
    const waited = Date.now() - started;

    assert.equal(response.status, 200);
    assert.ok(waited >= 1900 && waited < 3000, `waited ${waited} ms`);
  });

  it('does not ask the gateway when no bus has GPS', async () => {
    mockUpstream(() =>
      Response.json([
        { linea: '145', minutos: 12, real: false, idEmpresa: null, idBus: null },
      ]),
    );
    const gateway = gatewayNamespace(() => assert.fail('gateway called'));

    const { response } = await call('/v1/stops/3140/arrivals', { gateway });
    assert.equal(response.status, 200);
    assert.equal((await response.json()).arrivals[0].vehicle, null);
    assert.deepEqual(gateway.paths, []);
  });
});

describe('routes served by ImGateway', () => {
  it('GET /v1/lines/{line}/buses passes the answer on, cached for 15 s', async () => {
    const body = { fetchedAt: '2026-10-19T22:52:10.000Z', buses: [] };
    const gateway = gatewayNamespace(() => Response.json(body));

    const { response } = await call('/v1/lines/D10/buses', { gateway });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('Cache-Control'), 'public, max-age=15');
    assert.deepEqual(await response.json(), body);
    assert.deepEqual(gateway.paths, ['/lines/D10/buses']);
  });

  it('GET /v1/catalog/{stops|lines} are cached for a day', async () => {
    const gateway = gatewayNamespace(() => Response.json({ stops: [] }));

    for (const name of ['stops', 'lines']) {
      const { response } = await call(`/v1/catalog/${name}`, { gateway });
      assert.equal(response.headers.get('Cache-Control'), 'public, max-age=86400');
    }
    assert.deepEqual(gateway.paths, ['/catalog/stops', '/catalog/lines']);
  });

  it('passes gateway errors on, not cached', async () => {
    const gateway = gatewayNamespace(() =>
      Response.json(
        { error: 'upstream_busy' },
        { status: 503, headers: { 'Retry-After': '42' } },
      ),
    );

    const { response } = await call('/v1/lines/117/buses', { gateway });
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.equal(response.headers.get('Retry-After'), '42');
    assert.deepEqual(await response.json(), { error: 'upstream_busy' });
  });

  it('answers 502 when the gateway throws', async () => {
    const gateway = gatewayNamespace(() => {
      throw new Error('Durable Object reset');
    });

    const { response } = await call('/v1/catalog/stops', { gateway });
    assert.equal(response.status, 502);
  });

  it('answers 503 not_configured without the binding', async () => {
    const { response } = await call('/v1/lines/117/buses');
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), { error: 'not_configured' });
  });
});

describe('GET /v1/stops/{id}/schedule/{day}/{H:MM}', () => {
  it('maps the timetable for the day type, cached for 6 h', async () => {
    const calls = mockUpstream(() =>
      new Response(fixture('transporte_rest/schedule_3140_habil_805.json')),
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

describe('unexpected errors', () => {
  it('respond() answers 500 internal_error as JSON, not cached', async () => {
    const logs = captureLogs();
    const response = await respond(
      () => {
        throw new TypeError("Cannot read properties of undefined (reading 'x')");
      },
      {},
      [],
    );

    assert.equal(response.status, 500);
    assert.equal(response.headers.get('Content-Type'), 'application/json; charset=utf-8');
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    assert.deepEqual(await response.json(), { error: 'internal_error' });
    assert.deepEqual(logs, ['internal: TypeError']);
  });
});

describe('logs', () => {
  it('name the source and the kind of an upstream error', async () => {
    const logs = captureLogs();
    mockUpstream(() => new Response('Internal Server Error', { status: 500 }));
    await call('/v1/stops/3140/arrivals');

    assert.deepEqual(logs, ['transporteRest: HTTP 500']);
  });

  it('never carry a URL, a path or a query string', async () => {
    const logs = captureLogs();
    const failures = [
      () => new Response('Internal Server Error', { status: 500 }),
      () => new Response('<html>maintenance</html>'),
      () => Response.json({ unexpected: true }),
      () => {
        throw new DOMException('The operation timed out.', 'TimeoutError');
      },
      () => {
        throw new TypeError('fetch failed: https://api.montevideo.gub.uy/x?y=1');
      },
    ];
    for (const failure of failures) {
      mockUpstream(failure);
      await call('/v1/stops/3140/arrivals');
      await call('/v1/stops/3140/schedule/weekday/8:05');
    }
    // Comfort from the gateway fails on its own
    mockUpstream(() => new Response(fixture('transporte_rest/arrivals_574.json')));
    await call('/v1/stops/574/arrivals', {
      gateway: gatewayNamespace(() => {
        throw new Error('https://im-gateway/vehicles?ids=50:111 reset');
      }),
    });

    assert.equal(logs.length, failures.length * 2 + 1);
    for (const line of logs) {
      assert.ok(!line.includes('/siguientesParada'), line);
      assert.ok(!line.includes('?'), line);
      assert.ok(!line.includes('3140'), line);
    }
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
    ['/v1/lines/d10/buses', 404, 'not_found'],
    ['/v1/lines/1234567/buses', 404, 'not_found'],
    ['/v1/lines/117/buses?x=1', 400, 'bad_request'],
    ['/v1/catalog/variants', 404, 'not_found'],
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
    mockUpstream(() => new Response(fixture('transporte_rest/lineas_574.json')));
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
