// Smoke test of a running proxy: GETs the path of every contract case that
// answers 200 (../contract/v1/cases.json) and checks the status, the
// Cache-Control, the Content-Type and the keys of the body against the
// goldens. Live data differ from the goldens, so values are not compared.
//
//   node scripts/smoke.js https://mvd-transporte-proxy.<subdomain>.workers.dev
//
// No dependencies (Node 22+). Exits with 1 when a check fails. Run it
// against the deployed Worker before shipping a build that uses it: only
// there do the city's hosts see Cloudflare's addresses (see ../README.md).

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const CONTRACT = new URL('../contract/v1/', import.meta.url);
const ISO_MS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;
// The catalog may wait up to 20 s for a first stop index
const TIMEOUT_MS = 30000;

const contractJson = (path) => JSON.parse(readFileSync(new URL(path, CONTRACT), 'utf8'));

/**
 * Checks every 200 path of the contract on [baseUrl] and reports each one
 * with [log]. Returns the number of paths that failed.
 */
export async function smoke(baseUrl, { fetch = globalThis.fetch, log = console.log } = {}) {
  const base = baseUrl.replace(/\/+$/, '');
  const ok = contractJson('cases.json').filter((c) => c.status === 200);

  // Paths of one route share their keys: arrivals of 6325 may have buses
  const keysByRoute = new Map();
  for (const c of ok) {
    keysOf(contractJson(c.response), '', mapFor(keysByRoute, route(c.request)));
  }

  let failed = 0;
  for (const request of new Set(ok.map((c) => c.request))) {
    const cases = ok.filter((c) => c.request === request);
    const problems = [];
    let matched = [];
    try {
      const response = await fetch(base + request, {
        headers: { Accept: 'application/json' },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      const text = await response.text();
      const body = parse(text);
      const cacheControl = response.headers.get('Cache-Control');
      matched = cases.filter((c) => c.cacheControl === cacheControl).map((c) => c.id);

      if (response.status !== 200) {
        problems.push(`status ${response.status}${body?.error ? ` (${body.error})` : ''}`);
      } else {
        if (matched.length === 0) {
          const expected = cases.map((c) => c.cacheControl).join(' | ');
          problems.push(`Cache-Control "${cacheControl}", expected ${expected}`);
        }
        const contentType = response.headers.get('Content-Type');
        if (contentType !== 'application/json; charset=utf-8') {
          problems.push(`Content-Type "${contentType}"`);
        }
        if (body === undefined) {
          problems.push('body is not JSON');
        } else {
          problems.push(...compareKeys(body, keysByRoute.get(route(request))));
          if ('fetchedAt' in body && !ISO_MS.test(body.fetchedAt)) {
            problems.push(`fetchedAt "${body.fetchedAt}"`);
          }
        }
      }
    } catch (e) {
      problems.push(e.name === 'TimeoutError' ? `no answer in ${TIMEOUT_MS / 1000} s` : e.message);
    }

    if (problems.length === 0) {
      log(`OK    ${request}  (${matched.join(', ')})`);
    } else {
      failed++;
      log(`FAIL  ${request}  ${problems.join('; ')}`);
    }
  }
  return failed;
}

/** "/v1/stops/574/schedule/weekday/8:05" → "/v1/stops/{id}/schedule/weekday/8:05". */
function route(request) {
  return request.replace(/^\/v1\/stops\/\d+/, '/v1/stops/{id}');
}

function mapFor(map, key) {
  if (!map.has(key)) map.set(key, new Map());
  return map.get(key);
}

/** Adds to [out] the key set of every object in [value], by path ("stops[].location"). */
function keysOf(value, path, out) {
  if (Array.isArray(value)) {
    for (const item of value) keysOf(item, `${path}[]`, out);
  } else if (value !== null && typeof value === 'object') {
    const keys = Object.keys(value).sort().join(',');
    if (!out.has(path)) out.set(path, new Set());
    out.get(path).add(keys);
    for (const [key, item] of Object.entries(value)) {
      keysOf(item, path ? `${path}.${key}` : key, out);
    }
  }
  return out;
}

/** Objects of [body] whose keys no golden has at the same path. */
function compareKeys(body, golden) {
  const problems = [];
  for (const [path, keySets] of keysOf(body, '', new Map())) {
    for (const keys of keySets) {
      if (!golden.get(path)?.has(keys)) {
        const expected = [...(golden.get(path) ?? ['nothing'])].join(' | ');
        problems.push(`keys at "${path || '/'}": ${keys}, expected ${expected}`);
      }
    }
  }
  return problems;
}

function parse(text) {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const [baseUrl] = process.argv.slice(2);
  if (!baseUrl) {
    console.error('Usage: node scripts/smoke.js <baseUrl>');
    process.exit(2);
  }
  const failed = await smoke(baseUrl);
  console.log(failed === 0 ? 'All good.' : `${failed} failed.`);
  process.exit(failed === 0 ? 0 : 1);
}
