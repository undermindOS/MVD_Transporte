// MVD Transporte proxy — the app's single backend address.
//
// Fixed /v1 routes over five sources: transporteRest (arrivals, stops,
// timetables), notificacion (news), pci (GPS status), and the official IM
// API and geoserver, which only the ImGateway Durable Object calls (fleet,
// catalogs, the lines of every stop).
// Responses are cached by Workers Caching (wrangler.jsonc `cache`) for the
// Cache-Control set here: on a hit Cloudflare answers without running this
// code, so neither the IP limit nor the upstreams are touched. On a miss the
// client IP is counted first.

import {
  getArrivals,
  getSchedule,
  getStop,
  StopNotFoundError,
  UpstreamError,
} from './transporte_rest.js';
import { compareDirections } from './im_gateway.js';
import { getNewest } from './notificacion.js';
import { getGpsStatus } from './pci.js';
import { DAY_TYPES, isObject } from './rules.js';

export { ImGateway } from './im_gateway.js';

// Seconds
const STOP_TTL = 24 * 3600; // name and lines change rarely
// Directions unknown for now (stop metadata failed, slow or incomplete)
const STOP_WITHOUT_DIRECTIONS_TTL = 300;
const MISSING_STOP_TTL = 3600; // a new stop may appear
const ARRIVALS_TTL = 15; // the app refreshes every 30 s
const SCHEDULE_TTL = 6 * 3600; // same as the app's own timetable cache
const CATALOG_TTL = 24 * 3600;
// Catalog without lines (X-Lines: 0): ImGateway tries the stop index again
// after 15 min
const CATALOG_NO_LINES_TTL = 900;
const NEWS_TTL = 300; // new messages come every few days
const GPS_TTL = 60; // the app asks at most once a minute

// Comfort data is optional: arrivals do not wait longer for it
const VEHICLES_WAIT_MS = 2000;
// Directions are optional too: a stop does not wait longer for them
const STOP_META_WAIT_MS = 2000;

// Stop codes are positive ints; no leading zeros, so one stop = one cache key
const STOP = '([1-9]\\d{0,6})';
// "H:MM" only, as the app writes it: 8:05, never 08:05 or 8:5 (one cache key)
const TIME = '(0|[1-9]\\d?):([0-5]\\d)';
// Exported for the contract tests: every route needs a case
export const ROUTES = [
  [new RegExp(`^/v1/stops/${STOP}$`), stop],
  [new RegExp(`^/v1/stops/${STOP}/arrivals$`), arrivals],
  [new RegExp(`^/v1/stops/${STOP}/schedule/([a-z]+)/${TIME}$`), schedule],
  [/^\/v1\/catalog\/stops$/, catalog],
  [/^\/v1\/news$/, news],
  [/^\/v1\/status\/gps$/, gpsStatus],
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

/**
 * Runs a route handler and turns its errors into /v1 error answers, so the
 * client always gets JSON. Logs are fixed strings "<source>: <kind>": no URL,
 * path or IP (see ../contract/v1/README.md).
 */
export async function respond(handler, env, params) {
  try {
    return await handler(env, ...params);
  } catch (e) {
    if (e instanceof StopNotFoundError) {
      return error(404, 'stop_not_found', {
        'Cache-Control': `public, max-age=${MISSING_STOP_TTL}`,
      });
    }
    if (e instanceof UpstreamError) {
      console.error(`${e.source}: ${e.message}`);
      return e.timeout
        ? error(504, 'upstream_timeout')
        : error(502, 'upstream_error');
    }
    console.error(`internal: ${e?.name}`);
    return error(500, 'internal_error');
  }
}

async function stop(env, id) {
  const [details, directions] = await Promise.all([
    getStop(Number(id)),
    lookupDirections(env, id),
  ]);
  // Only lines transporteRest lists for the stop, sorted like the app
  const lines = new Set(details.lines);
  return json(
    {
      ...details,
      directions: (directions ?? [])
        .filter((d) => isObject(d) && lines.has(d.line))
        .sort(compareDirections),
    },
    directions ? STOP_TTL : STOP_WITHOUT_DIRECTIONS_TTL,
  );
}

/**
 * Where the lines of stop [id] go, from ImGateway's stop metadata; null
 * while they are unknown: the gateway failed, took longer than
 * STOP_META_WAIT_MS or has them incomplete. Without the binding there is
 * nothing to wait for: [].
 */
async function lookupDirections(env, id) {
  if (!env.IM_GATEWAY) return [];

  let timer;
  try {
    const response = await Promise.race([
      gateway(env, `/stops/${id}/meta`),
      new Promise((resolve) => {
        timer = setTimeout(resolve, STOP_META_WAIT_MS, null);
      }),
    ]);
    if (!response?.ok) return null;
    const { complete, directions } = await response.json();
    return complete === true && Array.isArray(directions) ? directions : null;
  } catch (e) {
    console.error(`im-gateway: ${e.name}`);
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function arrivals(env, id) {
  const { fetchedAtMs, arrivals: list } = await getArrivals(Number(id));
  const vehicles = await lookupVehicles(env, list);
  return json(
    {
      id: Number(id),
      // Cached up to ARRIVALS_TTL: lets the app tell how old the minutes are
      fetchedAt: new Date(fetchedAtMs).toISOString(),
      arrivals: list.map(({ _bus, ...arrival }) => {
        const comfort = (_bus && vehicles[_bus]) ?? null;
        return {
          ...arrival,
          airConditioning: comfort?.airConditioning ?? null,
          zeroEmission: comfort?.zeroEmission ?? null,
        };
      }),
    },
    ARRIVALS_TTL,
  );
}

/**
 * Comfort of the GPS buses in [list], by "companyId:busId". Empty when the
 * official API is not configured, busy or slow: arrivals never fail for it.
 */
async function lookupVehicles(env, list) {
  const ids = new Set(list.map((a) => a._bus).filter(Boolean));
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
    console.error(`im-gateway: ${e.name}`);
    return {};
  } finally {
    clearTimeout(timer);
  }
}

async function schedule(_env, id, day, hour, minute) {
  const h = Number(hour);
  if (!Object.hasOwn(DAY_TYPES, day) || h > 23) return error(400, 'bad_request');
  const passes = await getSchedule(Number(id), day, h, Number(minute));
  return json({ passes }, SCHEDULE_TTL);
}

function catalog(env) {
  return fromGateway(env, '/catalog/stops', (headers) =>
    headers.get('X-Lines') === '0' ? CATALOG_NO_LINES_TTL : CATALOG_TTL,
  );
}

async function news() {
  const items = await getNewest();
  return json({ fetchedAt: new Date().toISOString(), news: items }, NEWS_TTL);
}

async function gpsStatus() {
  const operators = await getGpsStatus();
  return json({ fetchedAt: new Date().toISOString(), operators }, GPS_TTL);
}

/**
 * Passes an ImGateway answer on, with this proxy's cache and error rules.
 * [maxAge] gives the TTL in seconds of a 200 from its headers, which are
 * not passed on.
 */
async function fromGateway(env, path, maxAge) {
  if (!env.IM_GATEWAY) return error(503, 'not_configured');

  let response;
  try {
    response = await gateway(env, path);
  } catch (e) {
    console.error(`im-gateway: ${e.name}`);
    return error(502, 'upstream_error');
  }
  if (response.ok) {
    return new Response(response.body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': `public, max-age=${maxAge(response.headers)}`,
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
