// The shared /v1 contract (../../contract/v1, see its README.md) for the
// proxy tests: the cases, their goldens and fakes of every upstream a case
// lists — the same captures the app's tests serve to its direct mode.

import { readFileSync } from 'node:fs';

import { ImGateway } from '../../src/index.js';

const CONTRACT = new URL('../../contract/v1/', import.meta.url);

/** A file of the contract folder, parsed. */
export function contractJson(path) {
  return JSON.parse(readFileSync(new URL(path, CONTRACT), 'utf8'));
}

export const cases = contractJson('cases.json');
export const directMasks = contractJson('direct_masks.json');

/**
 * Replaces `fetch` with the upstream entries of case [c], by exact URL, and
 * returns the list of URLs asked, in order. A URL the case does not list is
 * recorded and answered 599, so the URL check names it.
 */
export function mockFromCase(c) {
  const calls = [];
  const byUrl = new Map(c.upstream.map((entry) => [entry.url, entry]));
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return answer(byUrl.get(String(url)));
  };
  return calls;
}

/**
 * The `IM_GATEWAY` binding case [c] asks for, or null for `gateway: "none"`:
 * - `fake` answers the case's `https://im-gateway/…` entries and records the
 *   URLs in [calls];
 * - `real` is an ImGateway with test secrets and storage in memory; its own
 *   requests go out through the mocked `fetch`.
 * `settle()` waits for the work the gateway left running (`waitUntil`).
 */
export function gatewayFromCase(c, calls) {
  const pending = [];
  const settle = async () => {
    while (pending.length > 0) await Promise.allSettled(pending.splice(0));
  };
  if (c.gateway === 'none') return { binding: null, settle };

  let handle;
  if (c.gateway === 'real') {
    const im = new ImGateway(
      { storage: memoryStorage(), waitUntil: (p) => pending.push(p) },
      { IM_CLIENT_ID: 'id', IM_CLIENT_SECRET: 'secret' },
    );
    handle = (url) => im.fetch(new Request(url));
  } else {
    const byUrl = new Map(c.upstream.map((entry) => [entry.url, entry]));
    handle = async (url) => {
      calls.push(url);
      return answer(byUrl.get(url));
    };
  }

  const binding = {
    idFromName: (name) => name,
    get: () => ({ fetch: async (url) => handle(String(url)) }),
  };
  return { binding, settle };
}

/** The answer an upstream entry describes: `file`, `body` or a timeout. */
function answer(entry) {
  if (!entry) return new Response('not in the case', { status: 599 });
  if (entry.throw === 'timeout') {
    throw new DOMException('The operation timed out.', 'TimeoutError');
  }
  const body = entry.file ? readFileSync(new URL(entry.file, CONTRACT)) : entry.body;
  return new Response(body, { status: entry.status ?? 200, headers: entry.headers ?? {} });
}

/** Durable Object storage in memory. */
function memoryStorage() {
  const values = new Map();
  return {
    async get(key) {
      return structuredClone(values.get(key));
    },
    async put(key, value) {
      values.set(key, structuredClone(value));
    },
  };
}
