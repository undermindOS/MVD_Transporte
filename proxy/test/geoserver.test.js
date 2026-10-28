import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { UpstreamError } from '../src/errors.js';
import { getStopIndexCsv, parseCsv, STOP_INDEX_URL, toStopIndex } from '../src/geoserver.js';

// Rows of stops 546, 574, 3140 and 6325, 2026-10-27, shared with the app
// (../contract/v1): CRLF endings and an extra `ordinal` column, as sent
const sample = () =>
  readFileSync(
    new URL('../contract/v1/upstream/geoserver/stop_index_sample.csv', import.meta.url),
    'utf8',
  );

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** The index as plain sorted arrays, for deepEqual. */
function plain(index) {
  return Object.fromEntries(
    [...index].map(([id, { lines, variants }]) => [
      id,
      { lines: [...lines].sort(), variants: [...variants].sort((a, b) => a - b) },
    ]),
  );
}

describe('getStopIndexCsv', () => {
  it('asks for the three columns of the whole layer, without credentials', async () => {
    const calls = [];
    globalThis.fetch = async (url, init) => {
      calls.push([String(url), init.headers]);
      return new Response(sample());
    };

    assert.equal(await getStopIndexCsv(), sample());
    assert.equal(
      STOP_INDEX_URL,
      'https://geoserver.montevideo.gub.uy/geoserver/ows?service=wfs&version=2.0.0' +
        '&request=GetFeature&typeNames=imm:v_uptu_paradas&outputFormat=csv' +
        '&propertyName=cod_ubic_parada,desc_linea,cod_variante',
    );
    assert.deepEqual(calls.map(([url]) => url), [STOP_INDEX_URL]);
    assert.equal(calls[0][1].Authorization, undefined);
  });

  it('reports upstream errors as geoserver', async () => {
    globalThis.fetch = async () => new Response('', { status: 500 });
    await assert.rejects(getStopIndexCsv(), { source: 'geoserver', message: 'HTTP 500' });

    globalThis.fetch = async () => {
      throw new DOMException('The operation timed out.', 'TimeoutError');
    };
    await assert.rejects(getStopIndexCsv(), {
      source: 'geoserver',
      message: 'TimeoutError',
      timeout: true,
    });
  });
});

describe('toStopIndex', () => {
  it('reads lines and variants of each stop from the capture', () => {
    assert.deepEqual(plain(toStopIndex(sample())), {
      // No cod_variante on these rows
      546: { lines: ['144'], variants: [] },
      574: {
        lines: ['116', '117', '121', '141', '142', '144', '538'],
        variants: [630, 635, 833, 883, 2312, 2779, 3225, 3700, 3701, 4029, 7685, 7884, 8076, 8200, 8202],
      },
      3140: { lines: ['140', '143', '145', '494', '495'], variants: [] },
      6325: { lines: ['21', '427'], variants: [] },
    });
  });

  it('finds the columns by name, in any order, among extra ones', () => {
    const csv = [
      'cod_variante,x,desc_linea,FID,cod_ubic_parada',
      '630,1,116,f1,574',
      ',2,117,f2,574',
    ].join('\n');

    assert.deepEqual(plain(toStopIndex(csv)), {
      574: { lines: ['116', '117'], variants: [630] },
    });
  });

  it('reads quoted fields', () => {
    const csv = [
      '"FID","cod_ubic_parada","desc_linea","cod_variante"',
      '"f1","574","124 SD","630"',
      // A comma, a quote and a line break inside quotes
      '"f2",574,"A, ""B""\r\nC",',
    ].join('\r\n');

    assert.deepEqual(plain(toStopIndex(csv)), {
      574: { lines: ['124 SD', 'A, "B"\r\nC'], variants: [630] },
    });
  });

  it('keeps each line and variant once', () => {
    const csv = [
      'FID,cod_ubic_parada,desc_linea,cod_variante',
      'f1,3140,494,4414',
      'f2,3140,494,4414',
      'f3,3140, 494 ,4415',
    ].join('\r\n');

    assert.deepEqual(plain(toStopIndex(csv)), {
      3140: { lines: ['494'], variants: [4414, 4415] },
    });
  });

  it('skips rows without a valid stop id, and empty lines and variants', () => {
    const csv = [
      '﻿FID,cod_ubic_parada,desc_linea,cod_variante',
      'f1,,116,630',
      'f2,0574x,116,630',
      'f3,10000000,116,630',
      'f4,6325,,abc',
      '',
      'f5,6325,21,',
    ].join('\n');

    assert.deepEqual(plain(toStopIndex(csv)), {
      6325: { lines: ['21'], variants: [] },
    });
  });

  it('throws when a column is missing', () => {
    for (const csv of [
      'FID,cod_ubic_parada,desc_linea\nf1,574,116\n',
      '<?xml version="1.0"?><ows:ExceptionReport/>',
      '',
    ]) {
      assert.throws(
        () => toStopIndex(csv),
        (e) => e instanceof UpstreamError && e.source === 'geoserver' && e.message === 'unexpected shape',
      );
    }
  });

  it('throws when no stop is left, instead of an empty index', () => {
    assert.throws(() => toStopIndex('FID,cod_ubic_parada,desc_linea,cod_variante\r\n'), {
      source: 'geoserver',
      message: 'no stops',
    });
  });
});

describe('parseCsv', () => {
  it('splits CRLF, LF and CR rows and keeps empty fields', () => {
    assert.deepEqual(parseCsv('a,b\r\n1,\n,2\r3,4,'), [
      ['a', 'b'],
      ['1', ''],
      ['', '2'],
      ['3', '4', ''],
    ]);
  });

  it('reads a quote that does not close properly as plain text', () => {
    assert.deepEqual(parseCsv('"a"b,"c\n'), [['"a"b', '"c']]);
  });
});
