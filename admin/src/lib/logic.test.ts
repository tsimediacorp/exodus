import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { groupFor, bucket } from './ab.ts';
import { evaluate } from './version.ts';
import { normalize, DEFAULT_CONFIG } from './config.ts';

describe('who gets locked out', () => {
  test('a build below the minimum is blocked', () => {
    assert.equal(evaluate(44, 45, 45).updateRequired, true);
  });

  test('the minimum build itself is allowed through', () => {
    assert.equal(evaluate(45, 45, 45).updateRequired, false);
  });

  test('a newer build than we know about is fine', () => {
    assert.equal(evaluate(99, 45, 45).updateRequired, false);
  });

  test('no gate set means nobody is blocked', () => {
    assert.equal(evaluate(1, 0, 0).updateRequired, false);
  });

  test('an unreadable build is never locked out', () => {
    // A version-check bug that bricks every tester is far worse than one that
    // lets an old build through for a day.
    for (const build of [0, -1, NaN, Infinity]) {
      assert.equal(evaluate(build, 45, 45).updateRequired, false, String(build));
    }
  });

  test('the soft nudge is separate from the hard gate', () => {
    const gate = evaluate(44, 0, 45);
    assert.equal(gate.updateRequired, false);
    assert.equal(gate.updateAvailable, true);
  });
});

describe('A/B assignment', () => {
  test('a tester keeps their group across calls', () => {
    const first = groupFor('user-abc', 'salt', 50);
    for (let i = 0; i < 100; i++) {
      assert.equal(groupFor('user-abc', 'salt', 50), first);
    }
  });

  test('0 percent puts everyone in A, 100 puts everyone in B', () => {
    for (const id of ['a', 'b', 'c', 'longer-user-id-0001']) {
      assert.equal(groupFor(id, 's', 0), 'A');
      assert.equal(groupFor(id, 's', 100), 'B');
    }
  });

  test('a 50/50 split is actually near even', () => {
    let b = 0;
    const n = 4000;
    for (let i = 0; i < n; i++) {
      if (groupFor(`cognito-sub-${i}`, 'exodus', 50) === 'B') b++;
    }
    const share = (b / n) * 100;
    assert.ok(share > 45 && share < 55, `got ${share.toFixed(1)}% in B`);
  });

  test('changing the salt reshuffles', () => {
    const before = [];
    const after = [];
    for (let i = 0; i < 200; i++) {
      before.push(groupFor(`u${i}`, 'salt-one', 50));
      after.push(groupFor(`u${i}`, 'salt-two', 50));
    }
    const moved = before.filter((g, i) => g !== after[i]).length;
    assert.ok(moved > 60, `only ${moved} of 200 moved`);
  });

  test('buckets stay in range even for odd ids', () => {
    for (const id of ['', 'a', '😀', 'x'.repeat(500)]) {
      const value = bucket(id);
      assert.ok(Number.isInteger(value) && value >= 0 && value < 100, id.slice(0, 10));
    }
  });
});

describe('a stored config that is missing pieces still boots', () => {
  test('an empty blob yields the defaults', () => {
    const config = normalize({});
    assert.deepEqual(config.releases, DEFAULT_CONFIG.releases);
    assert.equal(config.ab.bPercent, 0);
  });

  test('garbage does not throw', () => {
    for (const raw of [null, undefined, 0, 'nope', []]) {
      assert.doesNotThrow(() => normalize(raw));
    }
  });

  test('a partial release keeps the other platform intact', () => {
    const config = normalize({ releases: { android: { minBuild: 45 } } });
    assert.equal(config.releases.android.minBuild, 45);
    assert.equal(config.releases.ios.minBuild, 0);
  });

  test('a percent outside 0-100 is clamped, not obeyed', () => {
    assert.equal(normalize({ ab: { bPercent: 500 } }).ab.bPercent, 100);
    assert.equal(normalize({ ab: { bPercent: -20 } }).ab.bPercent, 0);
    assert.equal(normalize({ ab: { bPercent: 'x' } }).ab.bPercent, 0);
  });

  test('a build number stored as a string still gates', () => {
    assert.equal(normalize({ releases: { android: { minBuild: '45' } } }).releases.android.minBuild, 45);
  });
});
