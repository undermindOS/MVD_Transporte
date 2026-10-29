import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { smoke } from '../scripts/smoke.js';
import { cases, contractJson } from './support/contract.js';

const okCases = cases.filter((c) => c.status === 200);

/**
 * A proxy that answers each 200 path with the golden of its first case,
 * changed by [edit(request, body)]; records the URLs asked.
 */
function fakeProxy(edit = (_request, body) => body) {
  const urls = [];
  const fetch = async (url) => {
    urls.push(url);
    const request = new URL(url).pathname;
    const c = okCases.find((x) => x.request === request);
    const body = edit(request, contractJson(c.response));
    if (body instanceof Response) return body;
    return Response.json(body, {
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Cache-Control': c.cacheControl,
      },
    });
  };
  return { fetch, urls };
}

describe('scripts/smoke.js', () => {
  it('passes a proxy that answers like the goldens, once per path', async () => {
    const { fetch, urls } = fakeProxy();
    const lines = [];

    const failed = await smoke('https://proxy.test/', { fetch, log: (l) => lines.push(l) });

    assert.equal(failed, 0);
    const paths = [...new Set(okCases.map((c) => c.request))];
    assert.deepEqual(urls, paths.map((p) => `https://proxy.test${p}`));
    assert.ok(lines.every((l) => l.startsWith('OK ')), lines.join('\n'));
    assert.ok(lines.some((l) => l.includes('/v1/stops/574  (stop.574)')));
  });

  it('accepts arrivals at a stop whose golden has none', async () => {
    const { fetch } = fakeProxy((request, body) =>
      request === '/v1/stops/6325/arrivals'
        ? contractJson('responses/arrivals_574.json')
        : body,
    );

    assert.equal(await smoke('https://proxy.test', { fetch, log: () => {} }), 0);
  });

  it('fails on another status, a missing or extra key, or another Cache-Control', async () => {
    const { fetch } = fakeProxy((request, body) => {
      if (request === '/v1/news') {
        return Response.json({ error: 'upstream_error' }, { status: 502 });
      }
      if (request === '/v1/stops/574/arrivals') {
        body.arrivals[0].realTime = true;
        return body;
      }
      if (request === '/v1/catalog/stops') {
        delete body.linesAvailable;
        return body;
      }
      if (request === '/v1/status/gps') {
        return Response.json(body, {
          headers: { 'Content-Type': 'application/json; charset=utf-8' },
        });
      }
      return body;
    });
    const lines = [];

    const failed = await smoke('https://proxy.test', { fetch, log: (l) => lines.push(l) });

    assert.equal(failed, 4);
    const failures = lines.filter((l) => l.startsWith('FAIL'));
    assert.match(failures.find((l) => l.includes('/v1/news')), /status 502 \(upstream_error\)/);
    assert.match(
      failures.find((l) => l.includes('/v1/stops/574/arrivals')),
      /keys at "arrivals\[\]": .*realTime/,
    );
    assert.match(failures.find((l) => l.includes('/v1/catalog/stops')), /keys at "\/"/);
    assert.match(failures.find((l) => l.includes('/v1/status/gps')), /Cache-Control "null"/);
  });
});
