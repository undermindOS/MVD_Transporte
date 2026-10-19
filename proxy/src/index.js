// MVD Transporte proxy — the app's single backend address.
//
// Fixed /v1 routes over transporteRest. Responses are cached by Workers
// Caching (wrangler.jsonc `cache`) for the Cache-Control set here: on a hit
// Cloudflare answers without running this code, so neither the IP limit nor
// transporteRest is touched. On a miss the client IP is counted first.

import {
  getArrivals,
  getSchedule,
  getStop,
  StopNotFoundError,
  UpstreamError,
} from './transporte_rest.js';

// Seconds
const STOP_TTL = 24 * 3600; // name and lines change rarely
const MISSING_STOP_TTL = 3600; // a new stop may appear
const ARRIVALS_TTL = 15; // the app refreshes every 30 s
const SCHEDULE_TTL = 6 * 3600; // same as the app's own timetable cache

const DAY_TYPES = { weekday: 'HABIL', saturday: 'SABADO', sunday: 'DOMINGO' };

// Stop codes are positive ints; no leading zeros, so one stop = one cache key
const STOP = '([1-9]\\d{0,6})';
const ROUTES = [
  [new RegExp(`^/v1/stops/${STOP}$`), stop],
  [new RegExp(`^/v1/stops/${STOP}/arrivals$`), arrivals],
  [new RegExp(`^/v1/stops/${STOP}/schedule/([a-z]+)/(\\d{1,2}):(\\d{2})$`), schedule],
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
      if (match) return respond(handler, match.slice(1));
    }
    return error(404, 'not_found');
  },
};

async function respond(handler, params) {
  try {
    return await handler(...params);
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

async function stop(id) {
  return json(await getStop(Number(id)), STOP_TTL);
}

async function arrivals(id) {
  const list = await getArrivals(Number(id));
  // Cached up to ARRIVALS_TTL: lets the app tell how old the minutes are
  return json({ fetchedAt: new Date().toISOString(), arrivals: list }, ARRIVALS_TTL);
}

async function schedule(id, day, hour, minute) {
  const h = Number(hour);
  const m = Number(minute);
  if (!Object.hasOwn(DAY_TYPES, day) || h > 23 || m > 59) {
    return error(400, 'bad_request');
  }
  const passes = await getSchedule(Number(id), DAY_TYPES[day], h, m);
  return json({ passes }, SCHEDULE_TTL);
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
