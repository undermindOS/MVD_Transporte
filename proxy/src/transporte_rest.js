// Client for transporteRest — the open backend of the official Cómo Ir web app
// (api.montevideo.gub.uy/transporteRest), no credentials — and the mapping of
// its answers to the /v1 contract (see ../README.md).

import { StopNotFoundError, UpstreamError } from './errors.js';
import { fetchUpstream } from './http.js';
import { isObject, schedulePath, text, toIntLoose as toInt } from './rules.js';

// im_api.js and im_gateway.js import the errors from here
export { StopNotFoundError, UpstreamError };

const SOURCE = 'transporteRest';
const BASE_URL = 'https://api.montevideo.gub.uy/transporteRest';
const TIMEOUT_MS = 8000;

/** Stop name and lines: `GET /lineas/{id}`. */
export async function getStop(stopId) {
  return toStop(stopId, await getJson(`${BASE_URL}/lineas/${stopId}`));
}

/** Upcoming buses, soonest first: `GET /siguientesParada/{id}`. */
export async function getArrivals(stopId) {
  return toArrivals(await getJson(`${BASE_URL}/siguientesParada/${stopId}`));
}

/**
 * Theoretical timetable, about 50 passes from hour:minute on, wrapping past
 * midnight: `GET /siguientesParada/{id}/{HABIL|SABADO|DOMINGO}/{H:MM}`.
 */
export async function getSchedule(stopId, day, hour, minute) {
  const { directUrl } = schedulePath({ stopId, day, hour, minute });
  return toSchedule(await getJson(directUrl));
}

async function getJson(url) {
  try {
    return await fetchUpstream(SOURCE, url, { timeoutMs: TIMEOUT_MS });
  } catch (e) {
    // The backend answers 500 "No existe la ubicación de parada con código 'N'."
    if (e.body?.trimStart().startsWith('No existe')) throw new StopNotFoundError();
    throw e;
  }
}

/**
 * `{"descripcion":"SAN JOSE y ANDES",
 *   "lineas":[{"descripcion":"116","codigo":38}, ...]}`
 */
export function toStop(stopId, data) {
  if (!isObject(data)) throw new UpstreamError('unexpected shape', { source: SOURCE });

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
 *    "idEmpresa":50,"idBus":247,"horaDesc":"7:39","coordinates":[lng,lat],
 *    "accesibilidad":true,"tipoAccesibilidad":2, ...}]`
 * Without GPS (`real:false`) `coordinates`, `idEmpresa` and `idBus` are null.
 * `busId` is internal: index.js matches it with the official API and drops it.
 */
export function toArrivals(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
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
      busId: toInt(item.idBus),
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
    throw new UpstreamError('unexpected shape', { source: SOURCE });
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
