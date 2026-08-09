#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if ! python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 11))'; then
  echo "rust sync requires Python 3.11 or newer" >&2
  exit 1
fi
exec python3 "$script_dir/check_rust_sync.py" "$@"
