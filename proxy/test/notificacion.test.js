import { afterEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { UpstreamError } from '../src/errors.js';
import { fetchNewest, getNewest, toNews, toNewsPage } from '../src/notificacion.js';

const API = 'https://api.montevideo.gub.uy/notificacion/mensajes?idApp=1&fromIdMessage=';

// Live pages of notificacion, 2026-10-27, shared with the app (../contract/v1)
const page = (from) =>
  readFileSync(
    new URL(`../contract/v1/upstream/notificacion/mensajes_from${from}.json`, import.meta.url),
    'utf8',
  );

const realFetch = globalThis.fetch;
afterEach(() => {
  globalThis.fetch = realFetch;
});

/** Serves the captured pages by fromIdMessage; 404 for the others. */
function mockPages() {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    const from = String(url).slice(API.length);
    return ['0', '136', '168', '172'].includes(from)
      ? new Response(page(from))
      : new Response('', { status: 404 });
  };
  return calls;
}

/** A page of [count] messages above `from`, holding ids [ids]. */
function fakePage(count, ids) {
  return { count, messages: ids.map((id) => ({ id })) };
}

describe('getNewest', () => {
  it('jumps 0 → 136 → 168 → 172 and returns that last page, newest first', async () => {
    const calls = mockPages();
    const news = await getNewest();

    assert.deepEqual(calls, [`${API}0`, `${API}136`, `${API}168`, `${API}172`]);
    assert.deepEqual(
      news.map((n) => n.id),
      [182, 181, 180, 179, 178, 177, 176, 175, 174, 173],
    );
  });

  it('fails when a page fails, instead of answering fewer news', async () => {
    const calls = [];
    globalThis.fetch = async (url) => {
      calls.push(String(url));
      return calls.length === 1 ? new Response(page(0)) : new Response('', { status: 500 });
    };

    await assert.rejects(getNewest(), (e) => {
      assert.ok(e instanceof UpstreamError);
      assert.equal(e.source, 'notificacion');
      assert.equal(e.message, 'HTTP 500');
      return true;
    });
    assert.deepEqual(calls, [`${API}0`, `${API}136`]);
  });

  it('reports a page that times out', async () => {
    globalThis.fetch = async () => {
      throw new DOMException('The operation timed out.', 'TimeoutError');
    };

    await assert.rejects(getNewest(), { source: 'notificacion', timeout: true });
  });

  it('sorts by date, then id, newest first', async () => {
    const message = (id, fecha) => ({ idMensaje: String(id), titulo: 'T', fecha });
    globalThis.fetch = async () =>
      Response.json({
        count: 4,
        messages: [message(7, 2000), message(9, 1000), message(8, 2000), message(6, 3000)],
      });

    assert.deepEqual(
      (await getNewest()).map((n) => n.id),
      [6, 8, 7, 9],
    );
  });
});

describe('fetchNewest', () => {
  it('jumps by count, not by the highest id of an out-of-order page', async () => {
    // From 136 the page holds 141…149 and then 171: going on from 171 would
    // skip 169 and 170. count − page size moves to 168 instead.
    const asked = [];
    const messages = await fetchNewest(async (from) => {
      asked.push(from);
      return toNewsPage(JSON.parse(page(from)));
    });

    assert.deepEqual(asked, [0, 136, 168, 172]);
    assert.deepEqual(
      toNewsPage(JSON.parse(page(136))).messages.map((m) => m.id).slice(-2),
      [149, 171],
    );
    assert.equal(messages.length, 10);
  });

  it('starts from the given id', async () => {
    const asked = [];
    await fetchNewest(async (from) => {
      asked.push(from);
      return fakePage(3, [41, 42, 43]);
    }, 40);

    assert.deepEqual(asked, [40]);
  });

  it('stops after 8 requests and takes the last page', async () => {
    const asked = [];
    const messages = await fetchNewest(async (from) => {
      asked.push(from);
      return fakePage(100, [from + 1, from + 2]);
    });

    assert.equal(asked.length, 8);
    assert.deepEqual(asked.slice(0, 3), [0, 98, 196]);
    assert.deepEqual(
      messages.map((m) => m.id),
      [asked[7] + 1, asked[7] + 2],
    );
  });

  it('fails when a page throws', async () => {
    let requests = 0;
    const getPage = async () => {
      requests++;
      if (requests === 2) throw new UpstreamError('HTTP 500', { source: 'notificacion' });
      return fakePage(20, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
    };

    await assert.rejects(fetchNewest(getPage), { message: 'HTTP 500' });
    assert.equal(requests, 2);
  });
});

describe('toNewsPage', () => {
  it('maps count and messages', () => {
    const { count, messages } = toNewsPage(JSON.parse(page(0)));

    assert.equal(count, 146);
    assert.deepEqual(
      messages.map((m) => m.id),
      [28, 29, 30, 35, 36, 37, 38, 39, 40, 41],
    );
  });

  it('counts the usable messages when count is missing', () => {
    const { count } = toNewsPage({
      messages: [{ idMensaje: '1', fecha: 1 }, { idMensaje: 'x', fecha: 2 }],
    });

    assert.equal(count, 1);
  });

  it('rejects any other shape', () => {
    for (const data of [null, [], {}, { count: 3 }, { messages: {} }]) {
      assert.throws(() => toNewsPage(data), { source: 'notificacion', message: 'unexpected shape' });
    }
  });
});

describe('toNews', () => {
  it('trims the texts, fixes the link and drops the user and topic', () => {
    assert.deepEqual(
      toNews({
        idUsuario: 'null',
        idMensaje: '182',
        titulo: 'Traslado definitivo de cuatro paradas ',
        mensajeCorto: 'Sobre Av. Rondeau, Paraguay y Gral. Aguilar ',
        mensajeCompleto: '<p>Por obras viales</p> \n',
        dataLink: 'https://Montevideo.gub.uy/node/99018',
        topicId: 1,
        fecha: 1793039282591,
      }),
      {
        id: 182,
        title: 'Traslado definitivo de cuatro paradas',
        summary: 'Sobre Av. Rondeau, Paraguay y Gral. Aguilar',
        // HTML is passed on: the app renders it with SafeHtml
        body: '<p>Por obras viales</p>',
        link: 'https://montevideo.gub.uy/node/99018',
        publishedAt: '2026-10-26T18:28:02.591Z',
      },
    );
  });

  it('accepts a date as text and missing texts', () => {
    assert.deepEqual(toNews({ idMensaje: 5, fecha: '1581096904776', dataLink: 'null' }), {
      id: 5,
      title: '',
      summary: '',
      body: '',
      link: null,
      publishedAt: '2020-02-07T17:35:04.776Z',
    });
  });

  it('skips a message without an id or a date', () => {
    for (const item of [
      { fecha: 1 },
      { idMensaje: 'abc', fecha: 1 },
      { idMensaje: '1' },
      { idMensaje: '1', fecha: 'ayer' },
      { idMensaje: '1', fecha: 9e15 },
      'garbage',
      null,
    ]) {
      assert.equal(toNews(item), null, JSON.stringify(item));
    }
  });
});
