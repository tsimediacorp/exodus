#!/usr/bin/env node
/**
 * Regenerate lib/amplify_outputs.dart from amplify_outputs.json.
 *
 * The Flutter app configures Amplify from `amplifyConfig`, a Dart string
 * constant — not from amplify_outputs.json, which is gitignored and therefore
 * absent in CI and on a fresh clone. That means every backend deploy has to be
 * mirrored into the Dart file or the app keeps talking to the previous shape
 * of the backend.
 *
 * Run after any deploy:
 *   npx ampx sandbox --once && npm run sync:outputs
 * CI does the same after `ampx pipeline-deploy` (see .github/workflows/deploy.yml).
 *
 * Exits non-zero on drift when --check is passed, so CI can fail loudly
 * instead of shipping a stale config.
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const jsonPath = resolve(root, 'amplify_outputs.json');
const dartPath = resolve(root, 'lib/amplify_outputs.dart');
const checkOnly = process.argv.includes('--check');

if (!existsSync(jsonPath)) {
  console.error(
    'amplify_outputs.json not found. Deploy the backend first:\n' +
      '  npx ampx sandbox --once        (local)\n' +
      '  npx ampx pipeline-deploy ...   (CI)',
  );
  process.exit(1);
}

const raw = readFileSync(jsonPath, 'utf8');

// Parse before writing so a truncated or half-written outputs file fails here
// rather than producing a Dart file that won't compile.
let parsed;
try {
  parsed = JSON.parse(raw);
} catch (err) {
  console.error(`amplify_outputs.json is not valid JSON: ${err.message}`);
  process.exit(1);
}

const pretty = JSON.stringify(parsed, null, 2);

// The Dart constant is a raw triple-quoted string, so the only sequence that
// could break out of it is ''' . It cannot occur in Amplify's output, but
// assert rather than emit a file that fails to compile.
if (pretty.includes("'''")) {
  console.error("amplify_outputs.json contains ''' which cannot be embedded in the Dart raw string.");
  process.exit(1);
}

const header = `// GENERATED — do not edit by hand.
//
// Mirrors amplify_outputs.json (which is gitignored) so the app has its
// backend config in a fresh clone and in CI. Regenerate after any deploy:
//   npm run sync:outputs
`;

const contents = `${header}const amplifyConfig = r'''${pretty}''';\n`;
const current = existsSync(dartPath) ? readFileSync(dartPath, 'utf8') : '';

if (current === contents) {
  console.log('lib/amplify_outputs.dart is already up to date.');
  process.exit(0);
}

if (checkOnly) {
  console.error(
    'lib/amplify_outputs.dart is stale — it does not match the deployed backend.\n' +
      'Run: npm run sync:outputs',
  );
  process.exit(1);
}

writeFileSync(dartPath, contents);

const models = Object.keys(parsed?.data?.model_introspection?.models ?? {});
console.log(
  `Wrote lib/amplify_outputs.dart` +
    (models.length ? ` (${models.length} models: ${models.join(', ')})` : ''),
);
