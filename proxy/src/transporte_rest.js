// Client for transporteRest — the open backend of the official Cómo Ir web app
// (api.montevideo.gub.uy/transporteRest), no credentials — and the mapping of
// its answers to the /v1 contract (see ../README.md).

const BASE_URL = 'https://api.montevideo.gub.uy/transporteRest';
const TIMEOUT_MS = 8000;
const HEADERS = {
  Accept: 'application/json',
  'User-Agent':
    'MVD-Transporte-proxy/0.1 (+https://github.com/undermindOS/MVD_Transporte)',
};

/** The stop code does not exist in the STM network. */
export class StopNotFoundError extends Error {}

/** transporteRest failed, timed out or answered something unusable. */
export class UpstreamError extends Error {
  constructor(message, { timeout = false } = {}) {
    super(message);
    this.timeout = timeout;
  }
}

/** Stop name and lines: `GET /lineas/{id}`. */
export async function getStop(stopId) {
  return toStop(stopId, await getJson(`/lineas/${stopId}`));
}

/** Upcoming buses, soonest first: `GET /siguientesParada/{id}`. */
export async function getArrivals(stopId) {
  return toArrivals(await getJson(`/siguientesParada/${stopId}`));
}

/**
 * Theoretical timetable, about 50 passes from hour:minute on, wrapping past
 * midnight: `GET /siguientesParada/{id}/{HABIL|SABADO|DOMINGO}/{H:MM}`.
 */
export async function getSchedule(stopId, dayType, hour, minute) {
  const time = `${hour}:${String(minute).padStart(2, '0')}`;
  return toSchedule(
    await getJson(`/siguientesParada/${stopId}/${dayType}/${time}`),
  );
}

async function getJson(path) {
  let response;
  try {
    response = await fetch(BASE_URL + path, {
      headers: HEADERS,
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
  } catch (e) {
    throw new UpstreamError(`${path}: ${e.name}`, {
      timeout: e.name === 'TimeoutError',
    });
  }

  const body = await response.text();
  if (!response.ok) {
    // The backend answers 500 "No existe la ubicación de parada con código 'N'."
    if (body.trimStart().startsWith('No existe')) {
      throw new StopNotFoundError(path);
    }
    throw new UpstreamError(`${path}: HTTP ${response.status}`);
  }

  try {
    return JSON.parse(body);
  } catch {
    throw new UpstreamError(`${path}: invalid JSON`);
  }
}

/**
 * `{"descripcion":"SAN JOSE y ANDES",
 *   "lineas":[{"descripcion":"116","codigo":38}, ...]}`
 */
export function toStop(stopId, data) {
  if (!isObject(data)) throw new UpstreamError('lineas: unexpected shape');

  const lines = [];
  for (const l of Array.isArray(data.lineas) ? data.lineas : []) {
    const name = isObject(l) ? text(l.descripcion) : '';
    if (name && !lines.includes(name)) lines.push(name);
  }

  const name = text(data.descripcion).trim();
  return { id: stopId, name: name || null, lines };
}

/**
 * `[{"linea":"145","minutos":5,"real":true,"destino":"PLAZA ESPAÑA",
 *    "idEmpresa":50,"horaDesc":"7:39","coordinates":[lng,lat],
 *    "accesibilidad":true,"tipoAccesibilidad":2, ...}]`
 * Without GPS (`real:false`) `coordinates` and `idEmpresa` are null.
 */
export function toArrivals(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('siguientesParada: unexpected shape');
  }

  const arrivals = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const line = text(item.linea);
    const etaMinutes = toInt(item.minutos);
    if (!line || etaMinutes === null) continue;

    const [lng, lat] = Array.isArray(item.coordinates) ? item.coordinates : [];
    arrivals.push({
      line,
      destination: text(item.destino),
      etaMinutes,
      realTime: item.real === true,
      scheduledTime: text(item.horaDesc) || null,
      companyId: toInt(item.idEmpresa),
      location:
        typeof lat === 'number' && typeof lng === 'number' ? { lat, lng } : null,
      accessible: item.accesibilidad === true,
      accessibilityType: toInt(item.tipoAccesibilidad),
    });
  }

  return arrivals.sort((a, b) => a.etaMinutes - b.etaMinutes);
}

/**
 * Same items as arrivals, with `minutos:null`, `real:false`:
 * `[{"linea":"145","destino":"PLAZA ESPAÑA","hora":803,"horaDesc":"8:03"}]`
 * Keeps the API order (chronological, wrapping past midnight).
 */
export function toSchedule(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('siguientesParada schedule: unexpected shape');
  }

  const passes = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const line = text(item.linea);
    const time = text(item.horaDesc);
    if (!line || !time) continue;
    passes.push({
      line,
      destination: text(item.destino),
      time,
      hhmm: toInt(item.hora),
    });
  }
  return passes;
}

function isObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function text(value) {
  return value === null || value === undefined ? '' : String(value);
}

/** Int from a number or a numeric string, otherwise null. */
function toInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    return Number.parseInt(value, 10);
  }
  return null;
}
