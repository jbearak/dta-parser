#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    cat <<'EOF'
Usage: scripts/bump-version.sh [major|minor|patch|X.Y.Z]

Bumps the npm, R, and Rust package versions, verifies the release, commits and
tags it, pushes it to origin, and publishes a GitHub Release. Publishing the
release triggers CI to build and attach the R binary packages.

Arguments:
  major       Increment the major version (X.0.0)
  minor       Increment the minor version (X.Y.0)
  patch       Increment the patch version (X.Y.Z) [default]
  X.Y.Z       Set an explicit stable version

Options:
  -h, --help  Show this help message
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi
if [[ $# -gt 1 ]]; then
    usage >&2
    exit 1
fi

BUMP_TYPE="${1:-patch}"
PACKAGE_JSON="$REPO_ROOT/typescript/dta-tools/package.json"
DESCRIPTION="$REPO_ROOT/r-package/dtatools/DESCRIPTION"
VERSION_FILES=(
    Cargo.lock
    typescript/dta-tools/package.json
    r-package/dtatools/DESCRIPTION
    r-package/dtatools/src/dta-tools/Cargo.toml
    r-package/dtatools/src/rust/Cargo.toml
    r-package/dtatools/src/rust/Cargo.lock
)
VERSION_CHANGES_STARTED=false

restore_version_files_on_failure() {
    status=$?
    if [[ $status -ne 0 && "$VERSION_CHANGES_STARTED" == true ]]; then
        echo "Release preparation failed; restoring version files." >&2
        git restore --staged --worktree -- "${VERSION_FILES[@]}"
    fi
    exit "$status"
}

trap restore_version_files_on_failure EXIT

cd "$REPO_ROOT"

for command in node bun cargo git gh; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Error: required command '$command' was not found" >&2
        exit 1
    fi
done

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working directory is not clean. Commit or stash changes first." >&2
    exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "Error: releases must be made from main (currently '$CURRENT_BRANCH')." >&2
    exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
    echo "Error: GitHub CLI authentication is unavailable; run 'gh auth login'." >&2
    exit 1
fi

CURRENT_VERSION="$(node -p "require('$PACKAGE_JSON').version")"
if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: current npm version '$CURRENT_VERSION' is not stable semver." >&2
    exit 1
fi

case "$BUMP_TYPE" in
    major) NEW_VERSION="$((BASH_REMATCH[1] + 1)).0.0" ;;
    minor) NEW_VERSION="${BASH_REMATCH[1]}.$((BASH_REMATCH[2] + 1)).0" ;;
    patch) NEW_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))" ;;
    [0-9]*.[0-9]*.[0-9]*) NEW_VERSION="$BUMP_TYPE" ;;
    *)
        echo "Error: invalid bump type or version '$BUMP_TYPE'." >&2
        usage >&2
        exit 1
        ;;
esac

if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: invalid stable version '$NEW_VERSION'." >&2
    exit 1
fi
if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "Error: new version is already $CURRENT_VERSION." >&2
    exit 1
fi

TAG="v$NEW_VERSION"
if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
    echo "Error: local tag '$TAG' already exists." >&2
    exit 1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Error: remote tag '$TAG' already exists." >&2
    exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Error: GitHub Release '$TAG' already exists." >&2
    exit 1
fi

R_VERSION="$(sed -n 's/^Version: //p' "$DESCRIPTION")"
if [[ "$R_VERSION" != "$CURRENT_VERSION" ]]; then
    echo "Note: synchronizing R version $R_VERSION with npm version $CURRENT_VERSION."
fi

echo "Bumping $CURRENT_VERSION to $NEW_VERSION"
VERSION_CHANGES_STARTED=true

node - "$NEW_VERSION" <<'NODE'
const fs = require("fs");
const version = process.argv[2];
const file = "typescript/dta-tools/package.json";
const packageJson = JSON.parse(fs.readFileSync(file, "utf8"));
packageJson.version = version;
fs.writeFileSync(file, JSON.stringify(packageJson, null, 2) + "\n");
NODE

node - "$NEW_VERSION" <<'NODE'
const fs = require("fs");
const version = process.argv[2];
const replacements = [
  ["r-package/dtatools/DESCRIPTION", /^Version: .*$/m, `Version: ${version}`],
  ["r-package/dtatools/src/dta-tools/Cargo.toml", /^version = ".*"$/m, `version = "${version}"`],
  ["r-package/dtatools/src/rust/Cargo.toml", /^version = ".*"$/m, `version = "${version}"`],
];
for (const [file, pattern, replacement] of replacements) {
  const input = fs.readFileSync(file, "utf8");
  const output = input.replace(pattern, replacement);
  if (output === input) throw new Error(`version was not updated in ${file}`);
  fs.writeFileSync(file, output);
}
NODE

node - "$NEW_VERSION" <<'NODE'
const fs = require("fs");
const version = process.argv[2];
const lockfiles = [
  ["Cargo.lock", ["dta-tools"]],
  ["r-package/dtatools/src/rust/Cargo.lock", ["dta-tools", "dtatools-r"]],
];
for (const [file, packageNames] of lockfiles) {
  let lock = fs.readFileSync(file, "utf8");
  for (const packageName of packageNames) {
    const pattern = new RegExp(`(\\[\\[package\\]\\]\\nname = "${packageName}"\\n)version = "[^"]+"`);
    if (!pattern.test(lock)) throw new Error(`package ${packageName} was not found in ${file}`);
    lock = lock.replace(pattern, `$1version = "${version}"`);
  }
  fs.writeFileSync(file, lock);
}
NODE

echo "Verifying TypeScript package"
bun --cwd typescript/dta-tools run typecheck
bun --cwd typescript/dta-tools test
bun --cwd typescript/dta-tools run build

echo "Verifying Rust and R release inputs"
cargo test --workspace --locked
scripts/check-r-cargo-vendor.sh

git diff --check
git add "${VERSION_FILES[@]}"
git commit -m "chore: bump version to $NEW_VERSION"
VERSION_CHANGES_STARTED=false
git tag -a "$TAG" -m "Version $NEW_VERSION"

echo "Pushing main and $TAG"
git push origin main
git push origin "$TAG"

echo "Publishing GitHub Release $TAG"
gh release create "$TAG" --verify-tag --generate-notes --title "$TAG"

echo "Released $TAG. npm publishing and R asset builds are now running in CI."
