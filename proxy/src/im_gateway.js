// ImGateway — Durable Object, the only caller of the official IM API.
//
// One instance serves the whole proxy (idFromName('global')), so whichever
// Cloudflare location a request comes from, the key never spends more than
// BUDGET_PER_MINUTE requests: the token, the fleet snapshot and the catalogs
// live here and are shared by every user. A stale copy is served while a
// fresh one loads, so a 4 s `GET /buses` never holds a request up.
//
// It also keeps the stop index: the lines of every stop, from one geoserver
// CSV a day. That request needs no key and never counts against the budget.
//
// Internal routes, called by the Worker (index.js), not by the app:
//   GET /vehicles?ids=50:111,10:22  comfort of buses by operator:bus id
//   GET /catalog/stops              stops with their lines
//   GET /lines/{line}/buses, /catalog/lines  no public route reaches them

import { getStopIndexCsv, toStopIndex } from './geoserver.js';
import {
  fetchToken,
  getJson,
  RateLimitedError,
  toFleet,
  toLineVariants,
  toStops,
  UnauthorizedError,
} from './im_api.js';
import { compareLines } from './rules.js';
import { UpstreamError } from './transporte_rest.js';

// The key allows 14 requests a minute (fixed window from :00); 2 are left
// for the owner's own checks with the same key. The count is kept in storage:
// memory does not survive hibernation (below).
export const BUDGET_PER_MINUTE = 12;

const FLEET_TTL_MS = 15 * 1000; // the app refreshes arrivals every 30 s
const CATALOG_TTL_MS = 24 * 3600 * 1000;
const TOKEN_MARGIN_MS = 30 * 1000; // tokens live 5 min

// How old a copy may be served when a fresh one cannot be loaded
const POSITIONS_MAX_AGE_MS = 2 * 60 * 1000;
const CATALOG_MAX_AGE_MS = 7 * 24 * 3600 * 1000;

// Comfort belongs to the vehicle: no bus changed it between two snapshots
// (842 buses, 2026-10-19). It is kept across fleet loads and in storage: with
// no timers or sockets this object hibernates after 10 s without requests and
// loses its memory, and the next arrivals are answered from storage at once
// instead of waiting ~4 s for GET /buses.
const COMFORT_MAX_AGE_MS = 24 * 3600 * 1000;
const COMFORT_SAVE_EVERY_MS = 5 * 60 * 1000; // ≤ 288 storage writes a day

// Stop index (geoserver.js): built at most once a day, served up to a week
// old. Stored as STOP_META_BUCKETS values "stopmeta:{id % 64}" of ~80 stops
// each, plus "stopmeta:info": a wake-up reads only the buckets it needs.
const STOP_META_TTL_MS = 24 * 3600 * 1000;
const STOP_META_MAX_AGE_MS = 7 * 24 * 3600 * 1000;
// After a failed build; the Worker caches a catalog without lines as long
const STOP_META_RETRY_MS = 15 * 60 * 1000;
// How long the catalog waits for a first build before answering without lines
const STOP_META_WAIT_MS = 20 * 1000;
export const STOP_META_BUCKETS = 64;

const RESOURCES = {
  fleet: { path: '/buses', map: toFleet, ttl: FLEET_TTL_MS },
  stops: { path: '/buses/busstops', map: toStops, ttl: CATALOG_TTL_MS },
  lines: { path: '/buses/linevariants', map: toLineVariants, ttl: CATALOG_TTL_MS },
};

/** IM_CLIENT_ID / IM_CLIENT_SECRET are not set (see ../README.md). */
export class NotConfiguredError extends Error {}

/** No budget left, or the API asked to wait; `retryAfter` is in seconds. */
export class BusyError extends UpstreamError {
  constructor(retryAfter) {
    super('IM API budget exhausted');
    this.retryAfter = retryAfter;
  }
}

export class ImGateway {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.now = () => Date.now();

    this.token = null; // {token, expiresAt}
    this.budget = null; // Promise of {minute, used, blockedUntil}, from storage
    this.copies = new Map(); // resource → {data, at}
    this.loading = new Map(); // resource or 'token' → Promise
    this.comfort = null; // {byKey: Map "companyId:busId" → comfort, at}
    this.comfortSavedAt = 0;
    this.stopMetaRead = null; // Promise of {info, buckets} or null, from storage
    this.stopMetaFailedAt = -Infinity;
  }

  async fetch(request) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/vehicles') {
        return await this.vehicles(url.searchParams.get('ids') ?? '');
      }
      const line = /^\/lines\/([0-9A-Z]{1,6})\/buses$/.exec(url.pathname);
      if (line) return await this.lineBuses(line[1]);
      if (url.pathname === '/catalog/stops') return await this.catalogStops();
      if (url.pathname === '/catalog/lines') {
        const { data, at } = await this.get('lines', CATALOG_MAX_AGE_MS);
        return reply({ fetchedAt: iso(at), variants: data });
      }
      return reply({ error: 'not_found' }, 404);
    } catch (e) {
      return failure(e);
    }
  }

  async vehicles(ids) {
    const { byKey, at } = await this.getComfort();
    const vehicles = {};
    for (const key of ids.split(',')) {
      const comfort = byKey.get(key);
      if (comfort) vehicles[key] = comfort;
    }
    return reply({ fetchedAt: iso(at), vehicles });
  }

  /**
   * Comfort of every bus seen so far: from memory, else from storage, else
   * from a fleet load. A stale fleet is reloaded in the background.
   */
  async getComfort() {
    if (!this.comfort) {
      const saved = await this.state?.storage?.get('comfort');
      if (saved) {
        this.comfort = { byKey: new Map(saved.entries), at: saved.at };
        this.comfortSavedAt = saved.at;
      }
    }
    if (this.comfort && this.now() - this.comfort.at < COMFORT_MAX_AGE_MS) {
      const fleet = this.copies.get('fleet');
      if (!fleet || this.now() - fleet.at >= FLEET_TTL_MS) {
        this.inBackground('fleet', this.load('fleet'));
      }
      return this.comfort;
    }
    await this.load('fleet');
    return this.comfort;
  }

  /** Adds the comfort of a fresh fleet to what is known; saves it now and then. */
  async remember(fleet) {
    const byKey = new Map(this.comfort?.byKey);
    for (const bus of fleet.data) {
      byKey.set(`${bus.companyId}:${bus.busId}`, {
        airConditioning: bus.airConditioning,
        zeroEmission: bus.zeroEmission,
      });
    }
    this.comfort = { byKey, at: fleet.at };

    if (this.state?.storage && fleet.at - this.comfortSavedAt >= COMFORT_SAVE_EVERY_MS) {
      this.comfortSavedAt = fleet.at;
      await this.state.storage.put('comfort', { entries: [...byKey], at: fleet.at });
    }
  }

  /**
   * The official stop catalog, each stop with its lines from the stop index
   * (sorted like the app). Without an index it waits up to
   * STOP_META_WAIT_MS for a build; if there is still none, every stop has
   * `lines: []`, `linesAvailable` is false and `X-Lines: 0` tells the
   * Worker to cache the answer briefly.
   */
  async catalogStops() {
    const [{ data, at }, buckets] = await Promise.all([
      this.get('stops', CATALOG_MAX_AGE_MS),
      this.allStopMeta(),
    ]);
    const linesOf = (id) => buckets?.[id % STOP_META_BUCKETS][id]?.lines ?? [];
    return reply(
      {
        fetchedAt: iso(at),
        linesAvailable: buckets !== null,
        stops: data.map((stop) => ({ ...stop, lines: linesOf(stop.id) })),
      },
      200,
      buckets ? {} : { 'X-Lines': '0' },
    );
  }

  /** Every bucket of the stop index, or null when there is none in time. */
  async allStopMeta() {
    const meta = (await this.stopMeta()) ?? (await this.waitForStopMeta());
    if (!meta) return null;
    return Promise.all(
      Array.from({ length: STOP_META_BUCKETS }, (_, i) => this.stopMetaBucket(meta, i)),
    );
  }

  /**
   * The stop index from memory, else from storage, while it is younger than
   * STOP_META_MAX_AGE_MS; otherwise null. One past its TTL is still served
   * while a new one is built in the background.
   */
  async stopMeta() {
    this.stopMetaRead ??= Promise.resolve(this.state?.storage?.get('stopmeta:info')).then(
      (info) => (info ? { info, buckets: [] } : null),
    );
    const meta = await this.stopMetaRead;
    const age = meta ? this.now() - meta.info.builtAt : Infinity;
    if (age >= STOP_META_MAX_AGE_MS) return null;
    if (age >= STOP_META_TTL_MS) this.buildStopMetaOnce();
    return meta;
  }

  /** Bucket [i] of [meta], `{byStop}` by stop id, read from storage once. */
  stopMetaBucket(meta, i) {
    meta.buckets[i] ??= Promise.resolve(this.state?.storage?.get(`stopmeta:${i}`)).then(
      (saved) => saved?.byStop ?? {},
    );
    return meta.buckets[i];
  }

  /** A first build, waited for at most STOP_META_WAIT_MS; null if none. */
  async waitForStopMeta() {
    const pending = this.buildStopMetaOnce();
    if (!pending) return null;
    let timer;
    try {
      return await Promise.race([
        pending,
        new Promise((resolve) => {
          timer = setTimeout(resolve, STOP_META_WAIT_MS, null);
        }),
      ]);
    } catch {
      return null; // logged by buildStopMetaOnce()
    } finally {
      clearTimeout(timer);
    }
  }

  /**
   * Starts a build of the stop index, unless one is running (single
   * flight) or the last one failed less than STOP_META_RETRY_MS ago.
   * Returns it, or null when none runs. A failure is logged once, here.
   */
  buildStopMetaOnce() {
    let pending = this.loading.get('stopMeta');
    if (pending) return pending;
    if (this.now() - this.stopMetaFailedAt < STOP_META_RETRY_MS) return null;

    pending = this.buildStopMeta()
      .catch((e) => {
        this.stopMetaFailedAt = this.now();
        throw e;
      })
      .finally(() => this.loading.delete('stopMeta'));
    this.loading.set('stopMeta', pending);
    const logged = pending.catch((e) =>
      console.error(
        e instanceof UpstreamError ? `${e.source}: ${e.message}` : `im-gateway: ${e.name}`,
      ),
    );
    this.state?.waitUntil?.(logged);
    return pending;
  }

  /** A new stop index from the whole geoserver layer, saved and kept. */
  async buildStopMeta() {
    // Straight to geoserver, never through call(): no token, no budget
    const index = toStopIndex(await getStopIndexCsv());

    const buckets = Array.from({ length: STOP_META_BUCKETS }, () => ({}));
    for (const [id, { lines }] of index) {
      buckets[id % STOP_META_BUCKETS][id] = { lines: [...lines].sort(compareLines) };
    }
    const info = { builtAt: this.now(), complete: true };

    // No await in between: storage writes them together, all or none
    const storage = this.state?.storage;
    await Promise.all([
      ...buckets.map((byStop, i) => storage?.put(`stopmeta:${i}`, { byStop })),
      storage?.put('stopmeta:info', info),
    ]);
    const meta = { info, buckets: buckets.map((byStop) => Promise.resolve(byStop)) };
    this.stopMetaRead = Promise.resolve(meta);
    return meta;
  }

  async lineBuses(line) {
    const { data, at } = await this.get('fleet', POSITIONS_MAX_AGE_MS);
    const buses = data
      .filter((bus) => bus.line === line)
      .map(({ line: _, ...bus }) => bus);
    return reply({ fetchedAt: iso(at), buses });
  }

  /**
   * A copy of [name] younger than its TTL; an older one up to [maxAge] while
   * a fresh copy loads in the background; otherwise waits for the load.
   */
  async get(name, maxAge) {
    const copy = this.copies.get(name);
    const age = copy ? this.now() - copy.at : Infinity;
    if (age < RESOURCES[name].ttl) return copy;
    if (age < maxAge) {
      this.inBackground(name, this.load(name));
      return copy;
    }
    return this.load(name);
  }

  /** A failed background load leaves the old copy in place. */
  inBackground(name, pending) {
    const logged = pending.catch((e) =>
      console.error(`im-gateway ${name}: ${e.message}`),
    );
    this.state?.waitUntil?.(logged);
  }

  /** Loads [name] once, however many requests ask for it meanwhile. */
  load(name) {
    let pending = this.loading.get(name);
    if (!pending) {
      const { path, map } = RESOURCES[name];
      pending = this.call(path)
        .then(async (raw) => {
          const copy = { data: map(raw), at: this.now() };
          this.copies.set(name, copy);
          if (name === 'fleet') await this.remember(copy);
          return copy;
        })
        .finally(() => this.loading.delete(name));
      this.loading.set(name, pending);
    }
    return pending;
  }

  async call(path, retried = false) {
    const token = await this.getToken();
    await this.spend();
    try {
      return await getJson(path, token);
    } catch (e) {
      if (e instanceof RateLimitedError) {
        const budget = await this.loadBudget();
        budget.blockedUntil = this.now() + e.retryAfter * 1000;
        await this.saveBudget(budget);
        throw new BusyError(e.retryAfter);
      }
      if (e instanceof UnauthorizedError && !retried) {
        this.token = null;
        return this.call(path, true);
      }
      throw e;
    }
  }

  /** Counts one request against the minute, or throws BusyError. */
  async spend() {
    const budget = await this.loadBudget();
    const now = this.now();
    if (now < budget.blockedUntil) {
      throw new BusyError(Math.ceil((budget.blockedUntil - now) / 1000));
    }
    const minute = Math.floor(now / 60000);
    if (budget.minute !== minute) Object.assign(budget, { minute, used: 0 });
    if (budget.used >= BUDGET_PER_MINUTE) {
      throw new BusyError(Math.ceil(((minute + 1) * 60000 - now) / 1000));
    }
    budget.used++;
    await this.saveBudget(budget);
  }

  /** Read once per wake-up; every request of this instance shares it. */
  loadBudget() {
    this.budget ??= Promise.resolve(this.state?.storage?.get('budget')).then(
      (saved) => saved ?? { minute: -1, used: 0, blockedUntil: 0 },
    );
    return this.budget;
  }

  async saveBudget(budget) {
    await this.state?.storage?.put('budget', { ...budget });
  }

  async getToken() {
    if (this.token && this.token.expiresAt - TOKEN_MARGIN_MS > this.now()) {
      return this.token.token;
    }
    const { IM_CLIENT_ID: id, IM_CLIENT_SECRET: secret } = this.env ?? {};
    if (!id || !secret) throw new NotConfiguredError();

    let pending = this.loading.get('token');
    if (!pending) {
      pending = fetchToken(id, secret, this.now())
        .catch((e) => {
          // A refused client secret will not get better by retrying at once
          throw e instanceof UnauthorizedError
            ? new UpstreamError(`token refused: ${e.message}`)
            : e;
        })
        .finally(() => this.loading.delete('token'));
      this.loading.set('token', pending);
    }
    this.token = await pending;
    return this.token.token;
  }
}

function failure(e) {
  if (e instanceof NotConfiguredError) {
    return reply({ error: 'not_configured' }, 503);
  }
  if (e instanceof BusyError) {
    return reply({ error: 'upstream_busy' }, 503, {
      'Retry-After': String(e.retryAfter),
    });
  }
  if (e instanceof UpstreamError) {
    console.error(`im-gateway ${e.message}`);
    return e.timeout
      ? reply({ error: 'upstream_timeout' }, 504)
      : reply({ error: 'upstream_error' }, 502);
  }
  throw e;
}

function reply(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...headers },
  });
}

function iso(ms) {
  return new Date(ms).toISOString();
}
