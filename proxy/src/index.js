// MVD Transporte proxy — the app's single backend address.
//
// Fixed /v1 routes over two sources: transporteRest (arrivals, stops,
// timetables) and the official IM API, which only the ImGateway Durable
// Object calls (fleet, catalogs). Responses are cached by Workers Caching
// (wrangler.jsonc `cache`) for the Cache-Control set here: on a hit
// Cloudflare answers without running this code, so neither the IP limit nor
// the upstreams are touched. On a miss the client IP is counted first.

import {
  getArrivals,
  getSchedule,
  getStop,
  StopNotFoundError,
  UpstreamError,
} from './transporte_rest.js';

export { ImGateway } from './im_gateway.js';

// Seconds
const STOP_TTL = 24 * 3600; // name and lines change rarely
const MISSING_STOP_TTL = 3600; // a new stop may appear
const ARRIVALS_TTL = 15; // the app refreshes every 30 s
const SCHEDULE_TTL = 6 * 3600; // same as the app's own timetable cache
const LINE_BUSES_TTL = 15; // ImGateway refreshes the fleet as often
const CATALOG_TTL = 24 * 3600;

// Comfort data is optional: arrivals do not wait longer for it
const VEHICLES_WAIT_MS = 2000;

const DAY_TYPES = { weekday: 'HABIL', saturday: 'SABADO', sunday: 'DOMINGO' };

// Stop codes are positive ints; no leading zeros, so one stop = one cache key
const STOP = '([1-9]\\d{0,6})';
// Line names as the official API writes them: "121", "D10", "CE1"
const LINE = '([0-9A-Z]{1,6})';
const ROUTES = [
  [new RegExp(`^/v1/stops/${STOP}$`), stop],
  [new RegExp(`^/v1/stops/${STOP}/arrivals$`), arrivals],
  [new RegExp(`^/v1/stops/${STOP}/schedule/([a-z]+)/(\\d{1,2}):(\\d{2})$`), schedule],
  [new RegExp(`^/v1/lines/${LINE}/buses$`), lineBuses],
  [/^\/v1\/catalog\/(stops|lines)$/, catalog],
];

export default {
  async fetch(request, env) {
    const ip = request.headers.get('CF-Connecting-IP') ?? 'unknown';
    const { success } = await env.IP_LIMITER.limit({ key: ip });
    if (!success) return error(429, 'rate_limited', { 'Retry-After': '60' });

    if (request.method !== 'GET') {
      return error(405, 'method_not_allowed', { Allow: 'GET' });
    }

    const url = new URL(request.url);
    // No route takes a query string; refusing one keeps cache keys canonical
    if (url.search) return error(400, 'bad_request');

    for (const [pattern, handler] of ROUTES) {
      const match = pattern.exec(url.pathname);
      if (match) return respond(handler, env, match.slice(1));
    }
    return error(404, 'not_found');
  },
};

async function respond(handler, env, params) {
  try {
    return await handler(env, ...params);
  } catch (e) {
    if (e instanceof StopNotFoundError) {
      return error(404, 'stop_not_found', {
        'Cache-Control': `public, max-age=${MISSING_STOP_TTL}`,
      });
    }
    if (e instanceof UpstreamError) {
      console.error(`transporteRest ${e.message}`);
      return e.timeout
        ? error(504, 'upstream_timeout')
        : error(502, 'upstream_error');
    }
    throw e;
  }
}

async function stop(_env, id) {
  return json(await getStop(Number(id)), STOP_TTL);
}

async function arrivals(env, id) {
  const list = await getArrivals(Number(id));
  const vehicles = await lookupVehicles(env, list);
  return json(
    {
      // Cached up to ARRIVALS_TTL: lets the app tell how old the minutes are
      fetchedAt: new Date().toISOString(),
      arrivals: list.map(({ busId, ...arrival }) => ({
        ...arrival,
        vehicle: vehicles[`${arrival.companyId}:${busId}`] ?? null,
      })),
    },
    ARRIVALS_TTL,
  );
}

/**
 * Comfort of the GPS buses in [list], by "companyId:busId". Empty when the
 * official API is not configured, busy or slow: arrivals never fail for it.
 */
async function lookupVehicles(env, list) {
  const ids = new Set();
  for (const a of list) {
    if (a.realTime && a.companyId !== null && a.busId !== null) {
      ids.add(`${a.companyId}:${a.busId}`);
    }
  }
  if (ids.size === 0 || !env.IM_GATEWAY) return {};

  let timer;
  try {
    const response = await Promise.race([
      gateway(env, `/vehicles?ids=${[...ids].join(',')}`),
      new Promise((resolve) => {
        timer = setTimeout(resolve, VEHICLES_WAIT_MS, null);
      }),
    ]);
    if (!response?.ok) return {};
    const { vehicles } = await response.json();
    return vehicles ?? {};
  } catch (e) {
    console.error(`im-gateway vehicles: ${e.message}`);
    return {};
  } finally {
    clearTimeout(timer);
  }
}

async function schedule(_env, id, day, hour, minute) {
  const h = Number(hour);
  const m = Number(minute);
  if (!Object.hasOwn(DAY_TYPES, day) || h > 23 || m > 59) {
    return error(400, 'bad_request');
  }
  const passes = await getSchedule(Number(id), DAY_TYPES[day], h, m);
  return json({ passes }, SCHEDULE_TTL);
}

function lineBuses(env, line) {
  return fromGateway(env, `/lines/${line}/buses`, LINE_BUSES_TTL);
}

function catalog(env, name) {
  return fromGateway(env, `/catalog/${name}`, CATALOG_TTL);
}

/** Passes an ImGateway answer on, with this proxy's cache and error rules. */
async function fromGateway(env, path, maxAge) {
  if (!env.IM_GATEWAY) return error(503, 'not_configured');

  let response;
  try {
    response = await gateway(env, path);
  } catch (e) {
    console.error(`im-gateway ${path}: ${e.message}`);
    return error(502, 'upstream_error');
  }
  if (response.ok) {
    return new Response(response.body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': `public, max-age=${maxAge}`,
      },
    });
  }

  const { error: code } = await response.json().catch(() => ({}));
  const retryAfter = response.headers.get('Retry-After');
  return error(
    response.status,
    code ?? 'upstream_error',
    retryAfter ? { 'Retry-After': retryAfter } : {},
  );
}

function gateway(env, path) {
  const stub = env.IM_GATEWAY.get(env.IM_GATEWAY.idFromName('global'));
  return stub.fetch(`https://im-gateway${path}`);
}

function json(body, maxAge) {
  return new Response(JSON.stringify(body), {
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': `public, max-age=${maxAge}`,
    },
  });
}

function error(status, code, headers = {}) {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      ...headers,
    },
  });
}
