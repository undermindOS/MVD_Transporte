// Client for the official IM transport API
// (api.montevideo.gub.uy/api/transportepublico, OAuth2 client credentials)
// and the mapping of its answers to the /v1 contract (see ../README.md).
//
// Only the ImGateway Durable Object calls it: the key allows 14 requests a
// minute for everybody (measured 2026-10-19, see ../../docs/REVIEW.md §2.3).

import { USER_AGENT } from './http.js';
import { UpstreamError } from './transporte_rest.js';

const TOKEN_URL =
  'https://mvdapi-auth.montevideo.gub.uy/auth/realms/pci/protocol/openid-connect/token';
const BASE_URL = 'https://api.montevideo.gub.uy/api/transportepublico';
// GET /buses takes ~4 s for the whole fleet
const TIMEOUT_MS = 10000;

// Operator names in the official API → ids used by transporteRest
const COMPANY_IDS = { COETC: 10, COME: 20, CUTCSA: 50, UCOT: 70 };

/** The API answered 429; `retryAfter` is in seconds. */
export class RateLimitedError extends UpstreamError {
  constructor(path, retryAfter) {
    super(`${path}: HTTP 429`);
    this.retryAfter = retryAfter;
  }
}

/** The token was refused (expired or revoked) — get a new one. */
export class UnauthorizedError extends UpstreamError {}

/** `{token, expiresAt}`, expiresAt in ms since epoch. */
export async function fetchToken(clientId, clientSecret, now = Date.now()) {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: clientId,
    client_secret: clientSecret,
  });
  const data = await request('token', TOKEN_URL, { method: 'POST', body });
  if (!isObject(data) || typeof data.access_token !== 'string') {
    throw new UpstreamError('token: unexpected shape');
  }
  const seconds = Number.isFinite(data.expires_in) ? data.expires_in : 300;
  return { token: data.access_token, expiresAt: now + seconds * 1000 };
}

/** `GET {path}` with a bearer token, parsed JSON. */
export function getJson(path, token) {
  return request(path, BASE_URL + path, {
    headers: { Authorization: `Bearer ${token}` },
  });
}

async function request(name, url, init) {
  let response;
  try {
    response = await fetch(url, {
      ...init,
      headers: { Accept: 'application/json', 'User-Agent': USER_AGENT, ...init.headers },
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    throw new UpstreamError(`${name}: ${e.name}`, {
      timeout: e.name === 'TimeoutError',
    });
  }

  const body = await response.text();
  if (response.status === 429) {
    const seconds = Number.parseInt(response.headers.get('Retry-After') ?? '', 10);
    throw new RateLimitedError(name, Number.isFinite(seconds) ? seconds : 60);
  }
  if (response.status === 401 || response.status === 403) {
    throw new UnauthorizedError(`${name}: HTTP ${response.status}`);
  }
  if (!response.ok) throw new UpstreamError(`${name}: HTTP ${response.status}`);

  try {
    return JSON.parse(body);
  } catch {
    throw new UpstreamError(`${name}: invalid JSON`);
  }
}

/**
 * `GET /buses` — every bus with GPS:
 * `[{"company":"CUTCSA","busId":111,"line":"117","lineVariantId":2779,
 *    "timestamp":"2026-10-19T19:51:57.000-03","speed":21,
 *    "location":{"type":"Point","coordinates":[lng,lat]},
 *    "destination":"PUNTA CARRETAS","access":"PISO BAJO",
 *    "thermalConfort":"Aire Acondicionado","emissions":"Euro V", ...}]`
 * Skips buses of unknown operators: they cannot be matched to arrivals.
 */
export function toFleet(data) {
  if (!Array.isArray(data)) throw new UpstreamError('buses: unexpected shape');

  const buses = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const companyId = COMPANY_IDS[item.company] ?? null;
    const busId = toInt(item.busId);
    const line = text(item.line);
    if (companyId === null || busId === null || !line) continue;

    buses.push({
      companyId,
      busId,
      line,
      variantId: toInt(item.lineVariantId),
      destination: text(item.destination),
      location: toLocation(item.location),
      speedKmh: toInt(item.speed),
      updatedAt: toIsoTime(item.timestamp),
      ...comfort(item),
    });
  }
  return buses;
}

/** What the rider can see from the stop. `null` = the API has no data. */
function comfort(item) {
  const thermal = text(item.thermalConfort);
  const emissions = text(item.emissions);
  return {
    airConditioning: thermal === 'Aire Acondicionado' ? true : null,
    zeroEmission:
      emissions === 'Cero emisiones'
        ? true
        : emissions && emissions !== 'Sin datos'
          ? false
          : null,
  };
}

/**
 * `GET /buses/busstops`:
 * `[{"busstopId":574,"street1":"SAN JOSE","street2":"ANDES",
 *    "location":{"type":"Point","coordinates":[lng,lat]}, ...}]`
 * The name follows transporteRest: "SAN JOSE y ANDES".
 */
export function toStops(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('busstops: unexpected shape');
  }

  const stops = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const id = toInt(item.busstopId);
    const location = toLocation(item.location);
    if (id === null || location === null) continue;
    const name = [text(item.street1).trim(), text(item.street2).trim()]
      .filter(Boolean)
      .join(' y ');
    stops.push({ id, name: name || null, location });
  }
  return stops;
}

/**
 * `GET /buses/linevariants`:
 * `[{"lineVariantId":8,"line":"402","origin":"PLAYA MALVÍN",
 *    "destination":"URUGUAY Y FLORIDA","subline":"CIUDAD VIEJA - MALVIN",
 *    "special":false, ...}]`
 */
export function toLineVariants(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('linevariants: unexpected shape');
  }

  const variants = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const id = toInt(item.lineVariantId);
    const line = text(item.line);
    if (id === null || !line) continue;
    variants.push({
      id,
      line,
      origin: text(item.origin),
      destination: text(item.destination),
      subline: text(item.subline),
      special: item.special === true,
    });
  }
  return variants;
}

/** GeoJSON Point → `{lat, lng}`, otherwise null. */
function toLocation(point) {
  const [lng, lat] =
    isObject(point) && Array.isArray(point.coordinates) ? point.coordinates : [];
  return typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : null;
}

/** "2026-10-19T19:51:57.000-03" (offset without minutes) → ISO in UTC. */
function toIsoTime(value) {
  const s = text(value).replace(/([+-]\d{2})$/, '$1:00');
  const ms = Date.parse(s);
  return Number.isNaN(ms) ? null : new Date(ms).toISOString();
}

function isObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function text(value) {
  return value === null || value === undefined ? '' : String(value);
}

function toInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number.parseInt(value, 10);
  }
  return null;
}
