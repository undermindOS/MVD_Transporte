// Client for pci buses/control — the share of each operator's buses whose
// GPS reaches the system, which the official Cómo Ir app shows
// (pci.montevideo.gub.uy/buses/control), no credentials — and its mapping
// to the /v1 contract (see ../contract/v1).

import { UpstreamError } from './errors.js';
import { fetchUpstream } from './http.js';
import { gpsOperator } from './rules.js';

const SOURCE = 'pci';
const CONTROL_URL = 'https://pci.montevideo.gub.uy/buses/control';
const TIMEOUT_MS = 5000; // answers in ~40 ms

/** GPS status per operator, in the API order. */
export async function getGpsStatus() {
  return toGpsStatus(await fetchUpstream(SOURCE, CONTROL_URL, { timeoutMs: TIMEOUT_MS }));
}

/**
 * `[{"empresa":"COETC", "valor":100}, …]` → `[{company, percent, partial}]`
 * (rules.js `gpsOperator`), skipping unusable items. Throws when nothing is
 * left: an empty list would read as "every operator is fine" and hide the
 * warning.
 */
export function toGpsStatus(data) {
  if (!Array.isArray(data)) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
  }
  const operators = data.map(gpsOperator).filter(Boolean);
  if (operators.length === 0) {
    throw new UpstreamError('no operators', { source: SOURCE });
  }
  return operators;
}
