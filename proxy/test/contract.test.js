import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import worker, { ROUTES } from '../src/index.js';
import {
  cases,
  contractJson,
  directMasks,
  gatewayFromCase,
  mockFromCase,
} from './support/contract.js';

const ISO_MS = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

// Cases whose behaviour arrives with a later commit of this branch, by the
// commit that brings it. Skipped and reported as such, never dropped: the
// list is empty once the proxy implements the whole contract.
const PENDING = {};

// Error codes no GET case can produce; index.test.js covers them
const CODES_WITHOUT_CASE = ['internal_error', 'method_not_allowed', 'rate_limited'];

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('contract /v1 cases', () => {
  for (const c of cases) {
    const pending = PENDING[c.id];
    it(c.id, { skip: pending && `pending ${pending}` }, async () => {
      const calls = mockFromCase(c);
      const { binding, settle } = gatewayFromCase(c, calls);
      const env = {
        IP_LIMITER: { limit: async () => ({ success: true }) },
        ...(binding && { IM_GATEWAY: binding }),
      };

      const response = await worker.fetch(new Request(`https://proxy.test${c.request}`), env);
      await settle();

      assert.equal(response.status, c.status);
      assert.equal(response.headers.get('Cache-Control'), c.cacheControl);
      assert.equal(response.headers.get('Content-Type'), 'application/json; charset=utf-8');
      for (const [name, value] of Object.entries(c.headers)) {
        assert.equal(response.headers.get(name), value, name);
      }

      // fetchedAt is the Worker's clock: only its format is fixed
      const { fetchedAt, ...body } = await response.json();
      const { fetchedAt: goldenFetchedAt, ...golden } = contractJson(c.response);
      assert.deepEqual(body, golden);
      if (goldenFetchedAt === undefined) {
        assert.equal(fetchedAt, undefined);
      } else {
        assert.match(fetchedAt, ISO_MS);
      }

      // Some routes ask upstreams in parallel: compared as multisets
      assert.deepEqual([...calls].sort(), c.upstream.map((e) => e.url).sort());
    });
  }
});

describe('contract /v1 files', () => {
  it('pending cases exist', () => {
    const ids = new Set(cases.map((c) => c.id));
    assert.deepEqual(Object.keys(PENDING).filter((id) => !ids.has(id)), []);
  });

  it('case ids are unique', () => {
    const ids = cases.map((c) => c.id);
    assert.equal(new Set(ids).size, ids.length);
  });

  it('masks are within direct_masks.json', () => {
    for (const c of cases) {
      for (const mask of c.direct?.mask ?? []) {
        assert.ok(directMasks.includes(mask), `${c.id}: ${mask}`);
      }
    }
  });

  it('every route has a case', () => {
    const paths = cases.map((c) => new URL(c.request, 'https://proxy.test').pathname);
    for (const [pattern] of ROUTES) {
      assert.ok(paths.some((p) => pattern.test(p)), `no case for ${pattern}`);
    }
  });

  it('every error code has a case', () => {
    // The codes as the Worker and ImGateway write them
    const source = ['index.js', 'im_gateway.js']
      .map((f) => readFileSync(new URL(`../src/${f}`, import.meta.url), 'utf8'))
      .join('\n');
    const codes = new Set(
      [...source.matchAll(/\berror\(\d{3}, '([a-z_]+)'|\{ error: '([a-z_]+)' \}/g)].map(
        (m) => m[1] ?? m[2],
      ),
    );
    for (const code of CODES_WITHOUT_CASE) {
      assert.ok(codes.has(code), `${code} is no longer answered`);
      codes.delete(code);
    }

    const covered = new Set(cases.map((c) => contractJson(c.response).error));
    assert.deepEqual([...codes].filter((code) => !covered.has(code)), []);
  });
});
