#!/usr/bin/env node
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const pubspecPath = join(root, 'apps/mobile/pubspec.yaml');
const nextVersion = process.argv[2];

if (!nextVersion) {
  console.error('Usage: pnpm release:version <MAJOR.MINOR.PATCH>');
  process.exit(1);
}

const versionPattern =
  /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?$/;
if (!versionPattern.test(nextVersion)) {
  console.error(`Invalid SemVer version: ${nextVersion}`);
  process.exit(1);
}

const pubspec = readFileSync(pubspecPath, 'utf8');
const currentLine = pubspec.match(/^version:\s*(\S+)\s*$/m);
if (!currentLine) {
  console.error('Could not find a version line in apps/mobile/pubspec.yaml');
  process.exit(1);
}

const currentValue = currentLine[1];
const [currentVersion, currentBuildText = '0'] = currentValue.split('+');
const currentBuild = Number(currentBuildText);

if (!Number.isSafeInteger(currentBuild) || currentBuild < 0) {
  console.error(`Invalid current build number: ${currentBuildText}`);
  process.exit(1);
}

if (currentVersion === nextVersion) {
  console.error(`Version is already ${nextVersion}; choose a new version.`);
  process.exit(1);
}

const nextBuild = currentBuild + 1;
const nextValue = `${nextVersion}+${nextBuild}`;
writeFileSync(pubspecPath, pubspec.replace(currentLine[0], `version: ${nextValue}`));

console.log(`Updated apps/mobile/pubspec.yaml: ${currentValue} -> ${nextValue}`);
console.log('Next: update CHANGELOG.md, open a PR, merge to main, then tag:');
console.log(`git tag -a v${nextVersion} -m "FStudy v${nextVersion}"`);
console.log(`git push origin v${nextVersion}`);
