#!/usr/bin/env bash
# Provision the pinned .NET SDK into repo-local .tools/ (gitignored).
# Reads the version from global.json (the single pin), downloads that exact
# build plus its published SHA512, verifies, and extracts. Re-running
# replaces .tools/dotnet with a fresh verified copy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RID="linux-x64"

for tool in python3 curl sha512sum tar; do
  command -v "$tool" >/dev/null || { echo "provision.sh: missing required tool: $tool" >&2; exit 1; }
done

VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["sdk"]["version"])' "$ROOT/global.json")"
test -n "$VERSION" || { echo "provision.sh: no sdk.version in $ROOT/global.json" >&2; exit 1; }

BASE="https://builds.dotnet.microsoft.com/dotnet/Sdk/${VERSION}/dotnet-sdk-${VERSION}-${RID}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/sdk.tar.gz" "$BASE.tar.gz"
curl -fsSL -o "$WORK/sdk.sha512" "$BASE.tar.gz.sha512"

EXPECTED="$(awk '{print $1}' "$WORK/sdk.sha512" | tr 'A-Z' 'a-z')"
ACTUAL="$(sha512sum "$WORK/sdk.tar.gz" | awk '{print $1}')"
test "$EXPECTED" = "$ACTUAL" || { echo "provision.sh: SHA512 mismatch for $BASE.tar.gz" >&2; exit 1; }

DEST="$ROOT/.tools/dotnet-$RID"
rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "$WORK/sdk.tar.gz" -C "$DEST"

export DOTNET_ROOT="$DEST" DOTNET_MULTILEVEL_LOOKUP=0 PATH="$DEST:$PATH"
dotnet --info
dotnet --list-sdks | grep -qF "${VERSION} [" || { echo "provision.sh: installed SDK is not $VERSION" >&2; exit 1; }
if [ -d "$ROOT/tools/githooks" ] && command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$ROOT" config core.hooksPath tools/githooks; then
    echo "provision.sh: git hooks wired to tools/githooks"
  else
    echo "provision.sh: warning: git config failed, hooks not wired" >&2
  fi
else
  echo "provision.sh: warning: tools/githooks not wired (no git checkout or dir missing)" >&2
fi
echo "provision.sh: .NET SDK $VERSION ready in $DEST"
