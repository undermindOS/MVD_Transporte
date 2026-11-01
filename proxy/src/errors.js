// Errors shared by every upstream client. index.js turns them into the /v1
// error answers and logs them as "<source>: <message>" (see respond()).

/** The stop code does not exist in the STM network. */
export class StopNotFoundError extends Error {}

/**
 * An upstream failed, timed out or answered something unusable.
 *
 * `source` names the upstream in logs ("transporteRest", "notificacion",
 * "pci"). The message is a fixed kind ("HTTP 500", "TimeoutError",
 * "invalid JSON", "unexpected shape"): never a URL or a path, so a log line
 * carries no stop id. `body` is what a non-2xx answer said, for callers that
 * tell errors apart; it is never logged.
 */
export class UpstreamError extends Error {
  constructor(message, { source = 'upstream', timeout = false, body = null } = {}) {
    super(message);
    this.source = source;
    this.timeout = timeout;
    this.body = body;
  }
}
