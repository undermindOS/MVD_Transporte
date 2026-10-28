import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { getGpsStatus, toGpsStatus } from '../src/pci.js';

const CONTROL = 'https://pci.montevideo.gub.uy/buses/control';

// Live answer of pci, 2026-10-27, shared with the app (../contract/v1)
const capture = () =>
  readFileSync(new URL('../contract/v1/upstream/pci/buses_control.json', import.meta.url), 'utf8');

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

describe('getGpsStatus', () => {
  it('maps every operator, in the API order', async () => {
    const calls = [];
    globalThis.fetch = async (url) => {
      calls.push(String(url));
      return new Response(capture());
    };

    assert.deepEqual(await getGpsStatus(), [
      { company: 'COETC', percent: 100, partial: false },
      { company: 'COME', percent: 100, partial: false },
      { company: 'CUTCSA', percent: 100, partial: false },
      { company: 'UCOT', percent: 100, partial: false },
    ]);
    assert.deepEqual(calls, [CONTROL]);
  });

  it('reports upstream errors as pci', async () => {
    globalThis.fetch = async () => new Response('', { status: 503 });

    await assert.rejects(getGpsStatus(), { source: 'pci', message: 'HTTP 503' });
  });
});

describe('toGpsStatus', () => {
  it('rounds and clamps to 0–100; partial below 70', () => {
    assert.deepEqual(
      toGpsStatus([
        { empresa: 'COETC', valor: 130 },
        { empresa: 'COME', valor: -2 },
        { empresa: 'CUTCSA', valor: 69.5 },
        { empresa: 'UCOT', valor: 55.4 },
      ]),
      [
        { company: 'COETC', percent: 100, partial: false },
        { company: 'COME', percent: 0, partial: true },
        { company: 'CUTCSA', percent: 70, partial: false },
        { company: 'UCOT', percent: 55, partial: true },
      ],
    );
  });

  it('skips items without a company or a numeric value', () => {
    assert.deepEqual(
      toGpsStatus([
        { empresa: '', valor: 50 },
        { empresa: 'COME', valor: '80' },
        { valor: 90 },
        'UCOT',
        null,
        { empresa: ' UCOT ', valor: 100 },
      ]),
      [{ company: 'UCOT', percent: 100, partial: false }],
    );
  });

  it('throws on [] or when no item is usable: never "all fine"', () => {
    for (const data of [[], [{ empresa: '', valor: 50 }, null]]) {
      assert.throws(() => toGpsStatus(data), { source: 'pci', message: 'no operators' });
    }
  });

  it('throws on any other shape', () => {
    for (const data of [null, {}, { empresa: 'COETC', valor: 100 }, 'COETC']) {
      assert.throws(() => toGpsStatus(data), { source: 'pci', message: 'unexpected shape' });
    }
  });
});
