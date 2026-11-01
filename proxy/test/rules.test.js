import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync } from 'node:fs';

import * as rules from '../src/rules.js';
import { contractJson } from './support/contract.js';

// Each vector file names its rule (../contract/v1/README.md); the app's
// rules_test.dart runs the same files against contract_rules.dart.
const RULES = {
  toIntLoose: (value) => rules.toIntLoose(value),
  trimText: (value) => rules.trimText(value),
  compareLines: (lines) => [...lines].sort(rules.compareLines),
  stopName: ([street, corner]) => rules.stopName(street, corner),
  arrival: ({ row, fetchedAt }) => rules.arrival(row, Date.parse(fetchedAt)),
  newsLink: (value) => rules.newsLink(value),
  gpsOperator: (item) => rules.gpsOperator(item),
  stopId: (id) => rules.isValidStopId(id),
  schedulePath: (request) => rules.schedulePath(request),
};

const files = readdirSync(new URL('../contract/v1/vectors/', import.meta.url))
  .filter((f) => f.endsWith('.json'))
  .sort();

describe('derivation rules', () => {
  it('every vector file has a rule', () => {
    const missing = files
      .map((f) => contractJson(`vectors/${f}`).rule)
      .filter((rule) => !Object.hasOwn(RULES, rule));
    assert.deepEqual(missing, []);
  });

  for (const file of files) {
    const { rule, cases } = contractJson(`vectors/${file}`);
    describe(`${file} (${rule})`, () => {
      cases.forEach(({ in: input, out }, i) => {
        it(`#${i} ${JSON.stringify(input).slice(0, 80)}`, () => {
          assert.deepEqual(RULES[rule](input), out);
        });
      });
    });
  }
});
