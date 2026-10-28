// GET helper for the upstreams without credentials (transporteRest,
// notificacion, pci, geoserver): one User-Agent, one timeout rule and errors
// with fixed kinds, so no log line ever carries a URL.

import { UpstreamError } from './errors.js';

export const USER_AGENT =
  'MVD-Transporte-proxy/0.3 (+https://github.com/undermindOS/MVD_Transporte)';

/**
 * `GET [url]`, parsed as JSON (`as: 'json'`) or returned as text.
 *
 * Throws UpstreamError from [source] whose message is one of:
 * - the error name when the request or the body fails ("TimeoutError" sets
 *   `timeout`);
 * - "HTTP {status}" for a non-2xx answer, with the answer in `body`;
 * - "invalid JSON".
 */
export async function fetchUpstream(source, url, { timeoutMs, as = 'json' } = {}) {
  let response;
  let body;
  try {
    response = await fetch(url, {
      headers: { Accept: as === 'json' ? 'application/json' : '*/*', 'User-Agent': USER_AGENT },
      signal: AbortSignal.timeout(timeoutMs),
    });
    body = await response.text();
  } catch (e) {
    throw new UpstreamError(e.name, { source, timeout: e.name === 'TimeoutError' });
  }

  if (!response.ok) {
    throw new UpstreamError(`HTTP ${response.status}`, { source, body });
  }
  if (as === 'text') return body;

  try {
    return JSON.parse(body);
  } catch {
    throw new UpstreamError('invalid JSON', { source });
  }
}
