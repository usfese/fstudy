#!/usr/bin/env node
// Keeps docs/knowledge honest. Usage:
//   node scripts/knowledge-check.mjs            # report drift in working tree (warnings)
//   node scripts/knowledge-check.mjs --strict   # exit 1 on any failure (used in CI)
//   node scripts/knowledge-check.mjs --base origin/main   # also check changes since base
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, normalize, relative } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/\/$/, '');
const knowledge = join(root, 'docs/knowledge');
const strict = process.argv.includes('--strict');
const baseIndex = process.argv.indexOf('--base');
const base = baseIndex > -1 ? process.argv[baseIndex + 1] : null;

const failures = [];
const warnings = [];

const read = (path) => readFileSync(join(root, path), 'utf8');
const git = (args) => execFileSync('git', args, { cwd: root, encoding: 'utf8' }).split('\n').filter(Boolean);

function markdownFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) return markdownFiles(full);
    return name.endsWith('.md') ? [full] : [];
  });
}

function slug(heading) {
  return heading.trim().toLowerCase()
    .replace(/[^\p{L}\p{N}\- _]/gu, '')
    .replace(/ /g, '-');
}

// 1. Relative links and anchors inside docs/knowledge.
for (const file of markdownFiles(knowledge)) {
  const text = readFileSync(file, 'utf8');
  for (const [, link] of text.matchAll(/\]\(([^)\s]+)\)/g)) {
    if (/^(https?:|mailto:)/.test(link)) continue;
    const [pathPart, anchor] = link.split('#');
    const target = pathPart ? normalize(join(dirname(file), pathPart)) : file;
    const where = relative(root, file);
    if (!existsSync(target)) {
      failures.push(`${where}: broken link -> ${link}`);
      continue;
    }
    if (anchor && target.endsWith('.md')) {
      const headings = [...readFileSync(target, 'utf8').matchAll(/^#+\s+(.+)$/gm)].map((m) => slug(m[1]));
      if (!headings.includes(anchor)) failures.push(`${where}: missing anchor -> ${link}`);
    }
  }
}

// 2. ADR index table must match the ADR headings.
const decisions = readFileSync(join(knowledge, 'decisions.md'), 'utf8');
const adrHeadings = [...decisions.matchAll(/^## (ADR-\d{3})/gm)].map((m) => m[1]);
const adrIndex = [...decisions.matchAll(/^\| (ADR-\d{3}) \|/gm)].map((m) => m[1]);
for (const id of adrHeadings) if (!adrIndex.includes(id)) failures.push(`decisions.md: ${id} missing from index table`);
for (const id of adrIndex) if (!adrHeadings.includes(id)) failures.push(`decisions.md: index lists ${id} but no section exists`);

// 3. OpenAPI document must cover every route registered in app.ts.
const app = read('apps/api/src/http/app.ts');
const openapiBlock = app.slice(app.indexOf('const OPENAPI_DOCUMENT'), app.indexOf('export function createApp'));
const documented = new Set([...openapiBlock.matchAll(/^ {4}'(\/[^']+)': \{/gm)].map((m) => m[1]));
const registered = new Set(
  [...app.matchAll(/app\.(?:get|post|put|patch|delete)\(\s*'(\/[^']+)'/g)]
    .map((m) => m[1].replace(/:(\w+)/g, '{$1}'))
    .filter((p) => p !== '/health' && p !== '/openapi.json'),
);
for (const path of registered) if (!documented.has(path)) failures.push(`OpenAPI missing route ${path} (apps/api/src/http/app.ts)`);
for (const path of documented) if (!registered.has(path)) warnings.push(`OpenAPI documents ${path} but no route is registered`);

// 4. Code changed without its nearest knowledge doc.
function nearestDoc(file) {
  let dir = dirname(file);
  while (dir && dir !== '.' && dir !== '/') {
    const candidate = join('docs/knowledge', dir, 'README.md');
    if (existsSync(join(root, candidate))) return candidate;
    dir = dirname(dir);
  }
  return null;
}
const ignored = /(^|\/)(node_modules|build|dist|\.dart_tool|\.wrangler|android|ios|web)\//;
const changed = new Set([
  ...git(['status', '--porcelain', '--untracked-files=all']).map((line) => line.slice(3).replace(/^"|"$/g, '')),
  ...(base ? git(['diff', '--name-only', `${base}...HEAD`]) : []),
]);
const codeChanged = [...changed].filter((f) => /^(apps|\.github|scripts)\//.test(f) && !ignored.test(f));
const docsChanged = new Set([...changed].filter((f) => f.startsWith('docs/knowledge/')));
const stale = new Set();
for (const file of codeChanged) {
  const doc = nearestDoc(file);
  if (doc && !docsChanged.has(doc)) stale.add(`${doc}  <- ${file}`);
}
for (const entry of stale) warnings.push(`docs may be stale: ${entry}`);

for (const line of failures) console.error(`FAIL  ${line}`);
for (const line of warnings) console.warn(`WARN  ${line}`);
if (failures.length === 0 && warnings.length === 0) console.log('knowledge check: ok');
if (strict && (failures.length > 0 || warnings.length > 0)) process.exit(1);
if (failures.length > 0) process.exit(1);
