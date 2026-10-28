// Derivation rules of the /v1 contract. The app implements each one again
// (lib/services/api/contract_rules.dart) for its direct mode; both sides run
// the same vectors in ../contract/v1/vectors/, so a change here without the
// Dart twin turns one of them red (see ../contract/v1/README.md).

const TRANSPORTE_REST_URL = 'https://api.montevideo.gub.uy/transporteRest';

// Path day → transporteRest day type
export const DAY_TYPES = { weekday: 'HABIL', saturday: 'SABADO', sunday: 'DOMINGO' };

// Uruguay has kept UTC−3 all year since 2015
const MONTEVIDEO_OFFSET_MS = -3 * 3600 * 1000;

// Below this share of buses with GPS an operator counts as partial (Cómo Ir)
const PARTIAL_PERCENT = 70;

// The widest time a Date holds, and a Dart DateTime too: ±10^8 days
const MAX_DATE_MS = 8.64e15;

export function isObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export function text(value) {
  return value === null || value === undefined ? '' : String(value);
}

/**
 * Int from a number (truncated) or a string that is `^-?\d+$` once trimmed,
 * otherwise null: "5.0", "+5" and booleans are not ints. Past ±(2^53 − 1)
 * also null: JS rounds there and Dart overflows, so neither has the value.
 */
export function toIntLoose(value) {
  let int = null;
  if (typeof value === 'number' && Number.isFinite(value)) {
    int = Math.trunc(value);
  } else if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    int = Number.parseInt(value.trim(), 10);
  }
  return Number.isSafeInteger(int) ? int : null;
}

/** `trim()`, also of U+0085, which JS keeps and Dart removes. */
export function trimText(value) {
  return value.replace(/^[\s\u0085]+|[\s\u0085]+$/g, '');
}

/**
 * Line order of the app (NearbyStopsService.compareLines): by the leading
 * number, lines with one first, ties by UTF-16 code units — never
 * localeCompare, which Dart cannot match.
 */
export function compareLines(a, b) {
  const na = leadingNumber(a);
  const nb = leadingNumber(b);
  if (na !== null && nb !== null && na !== nb) return na - nb;
  if ((na === null) !== (nb === null)) return na === null ? 1 : -1;
  return a < b ? -1 : a > b ? 1 : 0;
}

function leadingNumber(line) {
  const digits = /^\d+/.exec(line);
  return digits ? Number.parseInt(digits[0], 10) : null;
}

/** "SAN JOSE y ANDES"; one part alone when the other is empty; else null. */
export function stopName(street, corner) {
  const parts = [trimText(text(street)), trimText(text(corner))].filter(Boolean);
  return parts.length > 0 ? parts.join(' y ') : null;
}

/** Valid stop codes: one cache key and one upstream URL each. */
export function isValidStopId(id) {
  return Number.isInteger(id) && id >= 1 && id <= 9999999;
}

/** "H:MM" of [ms] in Montevideo, no leading hour zero. */
export function montevideoClock(ms) {
  const local = new Date(ms + MONTEVIDEO_OFFSET_MS);
  return `${local.getUTCHours()}:${String(local.getUTCMinutes()).padStart(2, '0')}`;
}

/** transporteRest's "08:05" → "8:05", trimmed; "" stays "". */
export function clockText(value) {
  return trimText(text(value)).replace(/^0(?=\d)/, '');
}

/**
 * One row of transporteRest `siguientesParada` → one /v1 arrival, or null
 * without a line or minutes, or when its time is past what a Date holds.
 * [fetchedAtMs] is when the answer arrived: it dates the minutes when the
 * row has no `time`. Comfort is unknown here (null); index.js fills it from
 * the official API.
 */
export function arrival(row, fetchedAtMs) {
  if (!isObject(row)) return null;
  const line = text(row.linea);
  const minutes = toIntLoose(row.minutos);
  if (!line || minutes === null) return null;

  const real = row.real === true;
  const etaMinutes = Math.max(0, minutes);
  const expectedMs =
    typeof row.time === 'number'
      ? row.time
      : Math.floor((fetchedAtMs + etaMinutes * 60000) / 60000) * 60000;
  // toISOString would throw: one bad row, not a 500 for the whole stop
  if (!(Math.abs(expectedMs) <= MAX_DATE_MS)) return null;
  const clockTime = clockText(row.horaDesc) || montevideoClock(expectedMs);
  const tripId =
    real && row.idEmpresa != null && row.idBus != null
      ? `bus-${row.idEmpresa}-${row.idBus}`
      : `sched-${row.variante ?? 0}-${row.hora ?? clockDigits(clockTime)}`;

  return {
    tripId,
    variantId: toIntLoose(row.variante),
    line,
    destination: text(row.destino),
    state: real && minutes <= 0 ? 'arriving' : real ? 'live' : 'scheduled',
    etaMinutes,
    expectedAt: new Date(expectedMs).toISOString(),
    clockTime,
    accessible: row.accesibilidad === true,
    airConditioning: null,
    zeroEmission: null,
  };
}

/** "8:05" → 805; null without digits. */
export function clockDigits(clock) {
  const digits = clock.replace(/\D/g, '');
  return digits ? Number.parseInt(digits, 10) : null;
}

/**
 * A news link the app may open: http(s) with a host, scheme and host in
 * lower case, the rest as written. Anything else ("", "null") → null.
 */
export function newsLink(value) {
  if (typeof value !== 'string') return null;
  const match = /^(https?):\/\/([^/?#]+)(.*)$/i.exec(trimText(value));
  if (!match) return null;
  const [, scheme, host, rest] = match;
  return `${scheme.toLowerCase()}://${host.toLowerCase()}${rest}`;
}

/**
 * `{"empresa":"UCOT","valor":55}` → `{company, percent, partial}`, or null
 * without a company or a numeric value.
 */
export function gpsOperator(item) {
  if (!isObject(item)) return null;
  const company = trimText(text(item.empresa));
  const value = item.valor;
  if (!company || typeof value !== 'number' || !Number.isFinite(value)) {
    return null;
  }
  const percent = Math.min(100, Math.max(0, Math.round(value)));
  return { company, percent, partial: percent < PARTIAL_PERCENT };
}

/**
 * Timetable request for [day] (weekday, saturday or sunday) from
 * hour:minute on: the path the app asks the proxy and the transporteRest URL
 * behind it. The time is canonical "H:MM", one cache key per minute.
 */
export function schedulePath({ stopId, day, hour, minute }) {
  const time = `${hour}:${String(minute).padStart(2, '0')}`;
  return {
    proxyPath: `/v1/stops/${stopId}/schedule/${day}/${time}`,
    directUrl: `${TRANSPORTE_REST_URL}/siguientesParada/${stopId}/${DAY_TYPES[day]}/${time}`,
  };
}
