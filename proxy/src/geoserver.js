// Client for the geoserver WFS layer imm:v_uptu_paradas — one row per stop,
// line and variant, the layer the app reads for nearby stops in direct mode
// (geoserver.montevideo.gub.uy), no credentials — and its reading into a
// stop index. Only ImGateway calls it, at most once a day: the whole layer
// is ~2.3 MB of CSV (~160 KB gzip, 0.7 s, 2026-10-27). It never needs the
// official API's key, so it never spends the key's budget.

import { UpstreamError } from './errors.js';
import { fetchUpstream } from './http.js';
import { isValidStopId, toIntLoose, trimText } from './rules.js';

const SOURCE = 'geoserver';
export const STOP_INDEX_URL =
  'https://geoserver.montevideo.gub.uy/geoserver/ows?service=wfs&version=2.0.0' +
  '&request=GetFeature&typeNames=imm:v_uptu_paradas&outputFormat=csv' +
  '&propertyName=cod_ubic_parada,desc_linea,cod_variante';
const TIMEOUT_MS = 20000;

// The columns asked for in STOP_INDEX_URL; others are ignored
const COLUMNS = ['cod_ubic_parada', 'desc_linea', 'cod_variante'];

/** The whole layer as CSV text. */
export function getStopIndexCsv() {
  return fetchUpstream(SOURCE, STOP_INDEX_URL, { timeoutMs: TIMEOUT_MS, as: 'text' });
}

/**
 * ```
 * FID,cod_ubic_parada,desc_linea,cod_variante
 * v_uptu_paradas.fid-7335d681_1a17d93b658_-3110,574,116,630
 * v_uptu_paradas.fid-7d73a8f2_1a17d863de4_-3b51,546,144,
 * ```
 * → `Map stop id → {lines: Set, variants: Set}`. Columns are found by their
 * header name, so their order and extra columns do not matter; a row has
 * one per line variant, so lines repeat. `cod_variante` is the official
 * API's `lineVariantId`, empty on some rows. Rows without a valid stop id
 * are skipped. Throws when a column is missing or no stop is left: an empty
 * index would read as "no stop has lines".
 */
export function toStopIndex(csv) {
  const [header = [], ...rows] = parseCsv(csv);
  const [idAt, lineAt, variantAt] = COLUMNS.map((name) =>
    header.findIndex((h) => trimText(h) === name),
  );
  if (idAt < 0 || lineAt < 0 || variantAt < 0) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
  }

  const index = new Map();
  for (const row of rows) {
    const id = toIntLoose(row[idAt] ?? '');
    if (id === null || !isValidStopId(id)) continue;
    let stop = index.get(id);
    if (!stop) {
      stop = { lines: new Set(), variants: new Set() };
      index.set(id, stop);
    }
    const line = trimText(row[lineAt] ?? '');
    if (line) stop.lines.add(line);
    const variant = toIntLoose(row[variantAt] ?? '');
    if (variant !== null) stop.variants.add(variant);
  }
  if (index.size === 0) throw new UpstreamError('no stops', { source: SOURCE });
  return index;
}

// One field and what ends it. A quoted field may hold commas, line breaks
// and "" for a quote; one that does not close properly is read as plain.
const FIELD = /(?:"((?:[^"]|"")*)"|([^,\r\n]*))(,|\r\n|\n|\r|$)/y;

/** Rows of [csv] (RFC 4180, CRLF or LF) as arrays of fields. */
export function parseCsv(csv) {
  const rows = [];
  let row = [];
  FIELD.lastIndex = csv.charCodeAt(0) === 0xfeff ? 1 : 0; // BOM
  while (FIELD.lastIndex < csv.length) {
    const [, quoted, plain, end] = FIELD.exec(csv);
    row.push(quoted === undefined ? plain : quoted.replaceAll('""', '"'));
    if (end !== ',') {
      rows.push(row);
      row = [];
    }
    if (end === '') break;
  }
  // "a,b," at the very end: the last field is empty
  if (row.length > 0) rows.push([...row, '']);
  return rows;
}
