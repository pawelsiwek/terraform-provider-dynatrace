#!/usr/bin/env bash
# verify.sh — hard gate for the da-aws-bump agent.
#
# Run from the fork root:  .github/agents/da-aws-bump/verify.sh
# Exits non-zero on any failure. Prints a final "OK" on success.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
PKG="./dynatrace/api/extensions/dac/awsmonitoring/..."
PKG_DIR="dynatrace/api/extensions/dac/awsmonitoring"

cd "$ROOT"

# --- 1. allowlist check -------------------------------------------------------
echo ">>> [1/8] allowlist check"
CHANGED_LIST="$(git diff --name-only HEAD --no-renames; git diff --name-only --cached --no-renames; git ls-files --others --exclude-standard)"
CHANGED_LIST="$(printf "%s\n" "$CHANGED_LIST" | sort -u | sed '/^$/d')"
if [[ -n "$CHANGED_LIST" ]]; then
  printf "%s\n" "$CHANGED_LIST" | python3 - "$HERE/ALLOWED_PATHS.txt" <<'PY'
import fnmatch, sys
allowed_path = sys.argv[1]
allowed = [l.strip() for l in open(allowed_path)
           if l.strip() and not l.lstrip().startswith("#")]
files = [l.strip() for l in sys.stdin if l.strip()]
bad = [f for f in files
       if not any(fnmatch.fnmatch(f, pat) for pat in allowed)]
if bad:
    print("FAIL: files outside ALLOWED_PATHS.txt:")
    for f in bad:
        print(f"  {f}")
    sys.exit(1)
PY
fi

# --- 2. CRLF check ------------------------------------------------------------
echo ">>> [2/8] CRLF check on changed files"
while IFS= read -r f; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  if file "$f" | grep -q CRLF; then
    echo "FAIL: CRLF line endings in $f"
    exit 1
  fi
done <<< "$CHANGED_LIST"

# --- 3. forbidden patterns ---------------------------------------------------
echo ">>> [3/8] forbidden-patterns scan"
if grep -RInE -f <(grep -v '^[[:space:]]*$\|^#' "$HERE/forbidden-patterns.txt") \
       "$PKG_DIR" 2>/dev/null; then
  echo "FAIL: forbidden pattern present (see matches above)"
  exit 1
fi

# --- 4. gofmt ----------------------------------------------------------------
echo ">>> [4/8] gofmt"
OUT="$(gofmt -l "$PKG_DIR" || true)"
[[ -z "$OUT" ]] || { echo "FAIL: gofmt:"; echo "$OUT"; exit 1; }

# --- 5. goimports ------------------------------------------------------------
echo ">>> [5/8] goimports"
if ! command -v goimports >/dev/null; then
  go install golang.org/x/tools/cmd/goimports@latest
  export PATH="$(go env GOPATH)/bin:$PATH"
fi
OUT="$(goimports -l "$PKG_DIR" || true)"
[[ -z "$OUT" ]] || { echo "FAIL: goimports:"; echo "$OUT"; exit 1; }

# --- 6. go vet ---------------------------------------------------------------
echo ">>> [6/8] go vet"
go vet "$PKG"

# --- 7. golangci-lint (best-effort; warn if unavailable) ---------------------
echo ">>> [7/8] golangci-lint"
if command -v golangci-lint >/dev/null; then
  golangci-lint run "$PKG"
else
  echo "  (golangci-lint not installed in sandbox — skipped; CI will catch)"
fi

# --- 8. tests + build --------------------------------------------------------
echo ">>> [8/8] tests + build"
go test -race -count=1 "$PKG"
go build ./...

echo
echo "OK"
