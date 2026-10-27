// Client for transporteRest — the open backend of the official Cómo Ir web app
// (api.montevideo.gub.uy/transporteRest), no credentials — and the mapping of
// its answers to the /v1 contract (see ../README.md).

import { StopNotFoundError, UpstreamError } from './errors.js';
import { fetchUpstream } from './http.js';
import {
  arrival,
  clockDigits,
  clockText,
  compareLines,
  isObject,
  schedulePath,
  text,
  toIntLoose,
  trimText,
} from './rules.js';

// im_api.js and im_gateway.js import the errors from here
export { StopNotFoundError, UpstreamError };

const SOURCE = 'transporteRest';
const BASE_URL = 'https://api.montevideo.gub.uy/transporteRest';
const TIMEOUT_MS = 8000;

/** Stop name and lines: `GET /lineas/{id}`. */
export async function getStop(stopId) {
  return toStop(stopId, await getJson(`${BASE_URL}/lineas/${stopId}`));
}

/**
 * Upcoming buses, soonest first: `GET /siguientesParada/{id}`.
 * `fetchedAtMs` is when the answer arrived: its minutes count from then.
 */
export async function getArrivals(stopId) {
  const data = await getJson(`${BASE_URL}/siguientesParada/${stopId}`);
  const fetchedAtMs = Date.now();
  return { fetchedAtMs, arrivals: toArrivals(data, fetchedAtMs) };
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
 * transporteRest does not know where the lines go: `directions` is left
 * empty (unknown), and the app falls back to the arrivals.
 */
export function toStop(stopId, data) {
  if (!isObject(data)) throw new UpstreamError('unexpected shape', { source: SOURCE });

  const lines = [];
  for (const l of Array.isArray(data.lineas) ? data.lineas : []) {
    const name = isObject(l) ? text(l.descripcion) : '';
    if (name && !lines.includes(name)) lines.push(name);
  }

  const name = trimText(text(data.descripcion));
  return { id: stopId, name: name || null, lines: lines.sort(compareLines), directions: [] };
}

/**
 * `[{"linea":"117","minutos":4,"real":true,"destino":"PUNTA CARRETAS",
 *    "idEmpresa":50,"idBus":111,"variante":2779,"hora":1956,
 *    "horaDesc":"19:56","time":1792450560000,"accesibilidad":true, ...}]`
 * Without GPS (`real:false`) `idEmpresa` and `idBus` are null. Each row
 * becomes a /v1 arrival (rules.js `arrival`) dated by [fetchedAtMs].
 * `_bus` ("companyId:busId" of a GPS bus, else null) is internal: index.js
 * matches it with the official API for comfort and drops it.
 */
export function toArrivals(data, fetchedAtMs) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
  }

  const arrivals = [];
  for (const row of data) {
    const item = arrival(row, fetchedAtMs);
    if (item) arrivals.push({ ...item, _bus: busKey(row) });
  }
  // sort() is stable: equal minutes keep the API order
  return arrivals.sort((a, b) => a.etaMinutes - b.etaMinutes);
}

function busKey(row) {
  const companyId = toIntLoose(row.idEmpresa);
  const busId = toIntLoose(row.idBus);
  return row.real === true && companyId !== null && busId !== null
    ? `${companyId}:${busId}`
    : null;
}

/**
 * Same items as arrivals, with `minutos:null`, `real:false`:
 * `[{"linea":"145","destino":"PLAZA ESPAÑA","hora":803,"horaDesc":"8:03"}]`
 * `time` is "H:MM" (from `hora` when `horaDesc` is empty) and `hhmm` is
 * never null (from the digits of `time` when `hora` is missing): a row with
 * neither is skipped. Keeps the API order (chronological, wrapping past
 * midnight).
 */
export function toSchedule(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
  }

  const passes = [];
  for (const item of data) {
    if (!isObject(item)) continue;
    const line = text(item.linea);
    const hora = toIntLoose(item.hora);
    const time = clockText(item.horaDesc) || hoursMinutes(hora);
    const hhmm = hora ?? clockDigits(time);
    if (!line || !time || hhmm === null) continue;
    passes.push({ line, destination: text(item.destino), time, hhmm });
  }
  return passes;
}

/** 805 → "8:05"; null → "". */
function hoursMinutes(hhmm) {
  if (hhmm === null) return '';
  return `${Math.floor(hhmm / 100)}:${String(hhmm % 100).padStart(2, '0')}`;
}
