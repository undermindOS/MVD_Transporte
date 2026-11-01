#!/usr/bin/env python3
"""Builds assets/rutas/horarios.bin, the timetable of the trip planner.

Sources (Intendencia de Montevideo open data, no keys):
  - uptu_pasada_variante.zip: every scheduled pass of every bus at every stop
  - WFS imm:v_uptu_lsv_destinos: cod_variante -> line name
  - WFS imm:v_uptu_paradas: stop coordinates and street names

Usage (local copies, see tool/rutas/README.md):
  python3 -I tool/rutas/build_horarios.py --pasadas uptu_pasada_variante.zip \
      --destinos destinos.json --paradas paradas.json --out assets/rutas/horarios.bin
or download the three into a new folder first:
  python3 -I tool/rutas/build_horarios.py --download /tmp/rutas-dl --out ...

Standard library only. The output is deterministic for the same inputs and
dates (gzip mtime 0), so tests can compare it byte for byte.

Format (little-endian, then gzip), version 1:
  header   magic "MVDR", u16 version, u32 built (yyyymmdd), u32 source date
           (yyyymmdd), u16 monday cutoff (minutes: on the day after a Sunday,
           hábil trips leaving before it do not run, the Sunday night service
           does)
  stops    u32 n; u32 id x n; i32 lat x n; i32 lon x n (micro-degrees);
           n x (u8 len, UTF-8 name)
  lines    u16 n; n x (u8 len, UTF-8 name)
  variants u16 n; u32 cod_variante x n; u16 line x n
  patterns u32 n; per pattern: u16 len, u16 stop x len
  routes   u32 n; per route: u32 pattern, u16 variant, u8 x (len - 1)
           minutes between consecutive stops, then for each day type (hábil,
           sábado, domingo): u16 count, u16 x count departures from the first
           stop, the first in minutes from the service day's midnight (may
           exceed 1440), the rest as differences to the previous one
Every trip of a route has the same stops and the same minutes between them,
so routes are FIFO (no trip overtakes another), as RAPTOR needs.
"""

import argparse
import collections
import csv
import datetime
import email.utils
import gzip
import io
import json
import os
import struct
import sys
import urllib.request
import zipfile

MAGIC = b'MVDR'
VERSION = 1
USER_AGENT = 'MVD-Transporte (github.com/undermindOS/MVD_Transporte)'
_WFS = ('https://geoserver.montevideo.gub.uy/geoserver/ows?service=wfs'
        '&version=2.0.0&request=GetFeature&outputFormat=application/json')
URLS = {
    'pasadas': 'https://datos-abiertos.montevideo.gub.uy/uptu_pasada_variante.zip',
    'destinos': _WFS + '&typeNames=imm:v_uptu_lsv_destinos'
                '&propertyName=cod_variante,desc_linea,desc_variante',
    'paradas': _WFS + '&typeNames=imm:v_uptu_paradas&srsName=EPSG:4326'
               '&propertyName=cod_ubic_parada,calle,esquina,the_geom',
}
FILE_NAMES = {
    'pasadas': 'uptu_pasada_variante.zip',
    'destinos': 'wfs_v_uptu_lsv_destinos.json',
    'paradas': 'wfs_v_uptu_paradas.json',
}
DAY_TYPES = (1, 2, 3)  # tipo_dia: hábil, sábado, domingo
HEADER = ['tipo_dia', 'cod_variante', 'frecuencia', 'cod_ubic_parada',
          'ordinal', 'hora', 'dia_anterior']


class Stats(collections.Counter):
    """Counts of what the build kept, dropped or repaired."""


def download(folder):
    """Fetches the three sources into a new, empty folder. Returns the
    yyyymmdd of the schedule zip's Last-Modified."""
    os.makedirs(folder, exist_ok=True)
    if os.listdir(folder):
        sys.exit(f'{folder} is not empty')
    source_date = None
    for key, url in URLS.items():
        req = urllib.request.Request(url, headers={'User-Agent': USER_AGENT})
        with urllib.request.urlopen(req, timeout=300) as resp:
            data = resp.read()
            if key == 'pasadas' and resp.headers.get('Last-Modified'):
                lm = email.utils.parsedate_to_datetime(
                    resp.headers['Last-Modified'])
                source_date = int(lm.strftime('%Y%m%d'))
        with open(os.path.join(folder, FILE_NAMES[key]), 'wb') as fh:
            fh.write(data)
        print(f'{FILE_NAMES[key]}: {len(data)} bytes', file=sys.stderr)
    return source_date


def file_date(path):
    """yyyymmdd of the CSV inside the zip, or of the file itself."""
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as z:
            y, m, d = z.infolist()[0].date_time[:3]
            return y * 10000 + m * 100 + d
    t = datetime.date.fromtimestamp(os.path.getmtime(path))
    return int(t.strftime('%Y%m%d'))


def read_pasadas(path):
    """Yields (tipo, variante, frecuencia, parada, ordinal, hora, flag)."""
    if zipfile.is_zipfile(path):
        z = zipfile.ZipFile(path)
        members = [i for i in z.infolist() if i.filename.endswith('.csv')]
        if len(members) != 1:
            sys.exit(f'{path}: expected one CSV, found {len(members)}')
        fh = io.TextIOWrapper(z.open(members[0]), encoding='utf-8',
                              newline='')
    else:
        fh = open(path, encoding='utf-8', newline='')
    with fh:
        reader = csv.reader(fh, delimiter=';')
        if next(reader) != HEADER:
            sys.exit(f'{path}: unexpected header')
        for row in reader:
            if not row:
                continue
            t, v, f, s, o, h, d = row
            yield int(t), int(v), int(f), int(s), int(o), int(h), d


def minutes(hmm):
    return hmm // 100 * 60 + hmm % 100


def timed(rows, stats, shift=0):
    """[(ordinal, stop, hmm)] -> [(stop, minute)] in ordinal order. Minutes
    never go back: past midnight the clock wraps (+1440); a small step back
    is a rounding glitch and keeps the previous minute."""
    out = []
    day = shift
    prev = None
    for _, stop, hmm in sorted(rows):
        m = minutes(hmm) + day
        if prev is not None and m < prev:
            if prev - m > 720:
                day += 1440
                m += 1440
            else:
                stats['minute steps back, clamped'] += 1
                m = prev
        out.append((stop, m))
        prev = m
    return out


def build_trips(rows, stats):
    """Service-day trips: [(day type, variante, [(stop, minute)])].

    A trip belongs to the day it leaves on. What the CSV says, by tipo_dia
    of the calendar day of each pass:
      - hábil lists whole trips, past midnight too (N, the clock wraps);
      - sábado repeats the Friday tails as S rows: dropped, hábil has them;
      - domingo has the Saturday tails as S rows: appended to sábado's trip;
      - domingo's * rows are passes on Monday: the tail of a Sunday trip
        when they follow its N rows, else a Sunday-night trip after
        midnight (minutes + 1440).
    """
    groups = collections.defaultdict(lambda: collections.defaultdict(list))
    for t, v, f, s, o, h, d in rows:
        if t not in DAY_TYPES or d not in ('N', 'S', '*'):
            stats['rows with unknown tipo_dia or dia_anterior'] += 1
            continue
        groups[(t, v, f)][d].append((o, s, h))
        stats[f'rows tipo {t} {d}'] += 1

    trips = []
    star_starts = []
    for (t, v, f), g in sorted(groups.items()):
        n = sorted(g.get('N', []))
        if t == 1:
            for flag in ('S', '*'):
                if flag in g:
                    stats[f'hábil {flag} groups dropped'] += 1
        if t == 2 and 'S' in g:
            wd = {o: h for o, _, h in groups.get((1, v, f), {}).get('N', [])}
            if all(wd.get(o) == h for o, _, h in g['S']):
                stats['sábado S tails (repeat hábil)'] += 1
            else:
                stats['sábado S tails without an hábil trip, dropped'] += 1
        if t == 2 and '*' in g:
            stats['sábado * groups dropped'] += 1
        if t == 3 and 'S' in g:
            sat = groups.get((2, v, f), {}).get('N', [])
            if not sat or min(g['S'])[0] != max(sat)[0] + 1:
                stats['domingo S tails without a sábado trip, dropped'] += 1
        if n:
            tail = []
            if t == 2:
                tail = groups.get((3, v, f), {}).get('S', [])
                if tail and min(tail)[0] != n[-1][0] + 1:
                    tail = []
                if tail:
                    stats['sábado trips continued by domingo S'] += 1
            if t == 3 and '*' in g and min(g['*'])[0] > n[-1][0]:
                tail = g['*']
                stats['domingo trips continued by *'] += 1
            trips.append((t, v, timed(n + tail, stats)))
        if t == 3 and '*' in g and not (n and min(g['*'])[0] > n[-1][0]):
            star = timed(g['*'], stats, shift=1440)
            star_starts.append(star[0][1] - 1440)
            trips.append((t, v, star))
            stats['Sunday-night trips after midnight (*)'] += 1
    # Monday's hábil trips before the last * departure would repeat the
    # night service the * rows already give.
    cutoff = max(star_starts) + 1 if star_starts else 0
    return trips, cutoff


def read_lines(path):
    with open(path, encoding='utf-8') as fh:
        features = json.load(fh)['features']
    out = {}
    for feat in features:
        p = feat['properties']
        out[int(p['cod_variante'])] = str(p['desc_linea']).strip()
    return out


def read_stops(path, stats):
    """cod_ubic_parada -> (lat, lon, name). One feature per stop x variant."""
    with open(path, encoding='utf-8') as fh:
        features = json.load(fh)['features']
    out = {}
    for feat in features:
        p = feat['properties']
        sid = int(p['cod_ubic_parada'])
        geom = feat.get('geometry')
        if sid in out:
            continue
        if not geom or not geom.get('coordinates'):
            continue
        lon, lat = geom['coordinates'][:2]
        calle = (p.get('calle') or '').strip()
        esquina = (p.get('esquina') or '').strip()
        name = f'{calle} y {esquina}' if calle and esquina else calle or esquina
        if not name:
            name = f'Parada {sid}'
            stats['stops without a street name'] += 1
        out[sid] = (round(lat * 1e6), round(lon * 1e6), name)
    return out


def build(pasadas, destinos, paradas, built_at, source_date):
    stats = Stats()
    trips, cutoff = build_trips(read_pasadas(pasadas), stats)
    line_of = read_lines(destinos)
    coords = read_stops(paradas, stats)

    scheduled = {s for _, _, tr in trips for s, _ in tr}
    missing = scheduled - coords.keys()
    stats['scheduled stops'] = len(scheduled)
    stats['scheduled stops without coordinates, dropped'] = len(missing)

    routes = collections.defaultdict(lambda: ([], [], []))
    for t, v, tr in trips:
        if v not in line_of:
            stats['trips of a variant without a line, dropped'] += 1
            continue
        kept = [(s, m) for s, m in tr if s in coords]
        if len(kept) < len(tr):
            stats['trips that lost a stop without coordinates'] += 1
        if len(kept) < 2:
            stats['trips with < 2 stops, dropped'] += 1
            continue
        first = kept[0][1]
        key = (v, tuple(s for s, _ in kept), tuple(m - first for _, m in kept))
        routes[key][DAY_TYPES.index(t)].append(first)
        stats['trips'] += 1

    stop_ids = sorted({s for _, seq, _ in routes for s in seq})
    stop_index = {s: i for i, s in enumerate(stop_ids)}
    variants = sorted({v for v, _, _ in routes})
    variant_index = {v: i for i, v in enumerate(variants)}
    lines = sorted({line_of[v] for v in variants})
    line_index = {name: i for i, name in enumerate(lines)}
    keys = sorted(routes, key=lambda k: (line_of[k[0]], k[0], k[1], k[2]))
    patterns = {}
    for v, seq, _ in keys:
        patterns.setdefault(seq, len(patterns))

    out = io.BytesIO()
    w = out.write
    w(MAGIC)
    w(struct.pack('<HIIH', VERSION, built_at, source_date, cutoff))

    w(struct.pack('<I', len(stop_ids)))
    w(struct.pack(f'<{len(stop_ids)}I', *stop_ids))
    w(struct.pack(f'<{len(stop_ids)}i', *(coords[s][0] for s in stop_ids)))
    w(struct.pack(f'<{len(stop_ids)}i', *(coords[s][1] for s in stop_ids)))
    for s in stop_ids:
        write_str(w, coords[s][2])

    w(struct.pack('<H', len(lines)))
    for name in lines:
        write_str(w, name)

    w(struct.pack('<H', len(variants)))
    w(struct.pack(f'<{len(variants)}I', *variants))
    w(struct.pack(f'<{len(variants)}H',
                  *(line_index[line_of[v]] for v in variants)))

    if len(stop_ids) > 0xFFFF or len(variants) > 0xFFFF:
        sys.exit('too many stops or variants for u16 indices')
    w(struct.pack('<I', len(patterns)))
    for seq in patterns:  # insertion order = index
        w(struct.pack(f'<H{len(seq)}H', len(seq),
                      *(stop_index[s] for s in seq)))

    w(struct.pack('<I', len(keys)))
    for key in keys:
        v, seq, offsets = key
        w(struct.pack('<IH', patterns[seq], variant_index[v]))
        steps = [b - a for a, b in zip(offsets, offsets[1:])]
        if max(steps) > 0xFF:
            sys.exit(f'variant {v}: {max(steps)} minutes between two stops')
        w(bytes(steps))
        for deps in routes[key]:
            deps.sort()
            w(struct.pack('<H', len(deps)))
            if deps:
                diffs = [deps[0]] + [b - a for a, b in zip(deps, deps[1:])]
                w(struct.pack(f'<{len(diffs)}H', *diffs))

    stats['stops'] = len(stop_ids)
    stats['lines'] = len(lines)
    stats['variants'] = len(variants)
    stats['patterns'] = len(patterns)
    stats['routes'] = len(keys)
    stats['monday cutoff (minutes)'] = cutoff
    raw = out.getvalue()
    stats['raw bytes'] = len(raw)
    return gzip.compress(raw, compresslevel=9, mtime=0), stats


def write_str(w, text):
    data = text.encode('utf-8')
    if len(data) > 0xFF:
        sys.exit(f'name too long: {text!r}')
    w(struct.pack('<B', len(data)))
    w(data)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--pasadas', help='uptu_pasada_variante.zip (or .csv)')
    ap.add_argument('--destinos', help='WFS imm:v_uptu_lsv_destinos JSON')
    ap.add_argument('--paradas', help='WFS imm:v_uptu_paradas JSON, EPSG:4326')
    ap.add_argument('--download', metavar='DIR',
                    help='fetch the three sources into this new folder first')
    ap.add_argument('--out', required=True)
    ap.add_argument('--built-at', type=int, help='yyyymmdd (default: today)')
    ap.add_argument('--source-date', type=int,
                    help='yyyymmdd (default: Last-Modified when downloading, '
                         'else the date of the CSV in the zip)')
    args = ap.parse_args()

    source_date = args.source_date
    if args.download:
        got = download(args.download)
        source_date = source_date or got
        for key in URLS:
            setattr(args, key, os.path.join(args.download, FILE_NAMES[key]))
    if not (args.pasadas and args.destinos and args.paradas):
        ap.error('give --pasadas, --destinos and --paradas, or --download')
    source_date = source_date or file_date(args.pasadas)
    built_at = args.built_at or int(datetime.date.today().strftime('%Y%m%d'))

    data, stats = build(args.pasadas, args.destinos, args.paradas, built_at,
                        source_date)
    with open(args.out, 'wb') as fh:
        fh.write(data)
    for key, value in stats.items():
        print(f'{key}: {value}', file=sys.stderr)
    print(f'{args.out}: {len(data)} bytes (gzip), source {source_date}, '
          f'built {built_at}', file=sys.stderr)


if __name__ == '__main__':
    main()
