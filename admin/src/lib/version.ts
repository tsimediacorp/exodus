/**
 * The app ships a monotonic build number (the +45 in "0.1.0+45"), and that is
 * what gates are written against. Semantic versions are for humans; build
 * numbers are the only thing that reliably increases, and comparing them is
 * an integer comparison rather than a parsing exercise.
 */
export interface Gate {
  updateRequired: boolean;
  updateAvailable: boolean;
}

export function evaluate(build: number, minBuild: number, latestBuild: number): Gate {
  // An unknown or malformed build must never be locked out: a version-check
  // bug that bricks every tester is far worse than one that lets an old build
  // through for a day.
  if (!Number.isFinite(build) || build <= 0) {
    return { updateRequired: false, updateAvailable: false };
  }
  return {
    updateRequired: build < minBuild,
    updateAvailable: build < latestBuild,
  };
}
