/**
 * Which A/B group a user is in.
 *
 * Deterministic from the user id, so a tester does not change group when the
 * app relaunches or the panel redeploys - an A/B result built on assignments
 * that drift is not a result. Changing the salt is the deliberate way to
 * reshuffle everyone.
 */
export function groupFor(userId: string, salt: string, bPercent: number): 'A' | 'B' {
  if (bPercent <= 0) return 'A';
  if (bPercent >= 100) return 'B';
  return bucket(`${salt}:${userId}`) < bPercent ? 'B' : 'A';
}

/** A stable 0-99 bucket. FNV-1a: small, fast, and spreads short ids well. */
export function bucket(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    // 32-bit FNV prime multiply, kept in range with Math.imul.
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash % 100;
}
