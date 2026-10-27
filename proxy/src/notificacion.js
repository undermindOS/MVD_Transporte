// Client for notificacion — the open news backend the official Cómo Ir app
// reads (api.montevideo.gub.uy/notificacion), no credentials — and the
// mapping of its messages to the /v1 contract (see ../contract/v1).

import { UpstreamError } from './errors.js';
import { fetchUpstream } from './http.js';
import { isObject, newsLink, text, toIntLoose, trimText } from './rules.js';

const SOURCE = 'notificacion';
const BASE_URL = 'https://api.montevideo.gub.uy/notificacion/mensajes';
// Cómo Ir's application id on the notification backend
const ID_APP = 1;
const TIMEOUT_MS = 5000; // per page
const MAX_REQUESTS = 8;
const MAX_NEWS = 10; // one page

/**
 * The newest messages, newest first (by date, then id): the last page of
 * fetchNewest() from the start, so a cold start gives the same list here and
 * in the app's direct mode. The app merges them into its own cache.
 */
export async function getNewest() {
  const news = await fetchNewest(getPage);
  return news
    .sort((a, b) => Date.parse(b.publishedAt) - Date.parse(a.publishedAt) || b.id - a.id)
    .slice(0, MAX_NEWS);
}

async function getPage(fromId) {
  const url = `${BASE_URL}?idApp=${ID_APP}&fromIdMessage=${fromId}`;
  return toNewsPage(await fetchUpstream(SOURCE, url, { timeoutMs: TIMEOUT_MS }));
}

/**
 * Finds the newest messages starting from id [from], one page after the
 * other (port of the app's TransportNewsService.fetchNewest).
 *
 * The endpoint returns at most 10 of the messages with an id above
 * `fromIdMessage`, in storage order (e.g. 141…149, 171), plus `count` of all
 * of them. Paging by the highest id received — what Cómo Ir does — therefore
 * skips messages. Instead `from` moves up until everything above it fits in
 * one page. Ids are near-sequential (the i-th id above `from` is at least
 * `from + i`), so the jump never overshoots the newest full page. After
 * MAX_REQUESTS pages the last one is taken as it is.
 */
export async function fetchNewest(getPage, from = 0) {
  for (let i = 0; ; i++) {
    const page = await getPage(from);
    if (page.count <= page.messages.length || i === MAX_REQUESTS - 1) {
      return page.messages;
    }
    from += page.count - page.messages.length;
  }
}

/**
 * `{"count":146,"messages":[{"idMensaje":"28", …}, …]}` → `{count, messages}`;
 * messages without an id or a date are skipped.
 */
export function toNewsPage(data) {
  if (!isObject(data) || !Array.isArray(data.messages)) {
    throw new UpstreamError('unexpected shape', { source: SOURCE });
  }
  const messages = data.messages.map(toNews).filter(Boolean);
  const count =
    typeof data.count === 'number' && Number.isFinite(data.count)
      ? Math.trunc(data.count)
      : messages.length;
  return { count, messages };
}

/**
 * One message:
 * `{"idUsuario":"null","idMensaje":"182","titulo":"Traslado … ",
 *   "mensajeCorto":"…","mensajeCompleto":"<p>…</p> \n",
 *   "dataLink":"https://Montevideo.gub.uy/node/99018","topicId":1,
 *   "fecha":1793039282591}`
 * → a /v1 news item, or null without an id or a date. `body` stays HTML or
 * plain text, as published; `idUsuario` and `topicId` are dropped.
 */
export function toNews(item) {
  if (!isObject(item)) return null;
  const id = toIntLoose(item.idMensaje);
  const ms = toIntLoose(item.fecha);
  const date = new Date(ms ?? Number.NaN);
  if (id === null || Number.isNaN(date.getTime())) return null;

  return {
    id,
    title: trimText(text(item.titulo)),
    summary: trimText(text(item.mensajeCorto)),
    body: trimText(text(item.mensajeCompleto)),
    link: newsLink(item.dataLink),
    publishedAt: date.toISOString(),
  };
}
