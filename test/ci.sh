#!/usr/bin/env bash
#
# test/ci.sh — PR-time validation. Runs locally AND in CI.
#
# Usage:
#   ./test/ci.sh              # run every check (default)
#   ./test/ci.sh <check>      # run one:
#                             #   syntax shellcheck whitespace crlf
#                             #   exec-bit smoke yaml gitleaks
#   ./test/ci.sh --help
#
# CI calls each subcommand as its own step so GitHub Actions shows
# per-check status. Locally, running without args runs them all and
# aborts at the first failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

step() { printf '\n==> %s\n' "$1"; }
in_ci() { [[ "${CI:-}" == "true" ]]; }

check_syntax() {
    step "bash syntax"
    bash -n bin/kafka-cli
}

check_shellcheck() {
    step "shellcheck"
    shellcheck bin/kafka-cli
}

# git grep exits 0 on match, 1 on no-match, >1 on real error. Treat each
# explicitly so a permission/IO failure doesn't look like "no match = green".
check_whitespace() {
    step "trailing whitespace"
    local hits rc=0
    # -I skips binaries; [[:blank:]] catches trailing tabs too.
    hits=$(git grep -HnI -E '[[:blank:]]+$') || rc=$?
    if (( rc == 0 )); then
        echo "::error::Trailing whitespace found:"
        echo "$hits"
        return 1
    elif (( rc != 1 )); then
        echo "::error::git grep exited $rc during whitespace scan"
        return 1
    fi
}

check_crlf() {
    step "LF line endings only"
    local hits rc=0
    hits=$(git grep -lI $'\r') || rc=$?
    if (( rc == 0 )); then
        echo "::error::CRLF line endings found in:"
        echo "$hits"
        return 1
    elif (( rc != 1 )); then
        echo "::error::git grep exited $rc during CRLF scan"
        return 1
    fi
}

check_exec_bit() {
    step "bin/kafka-cli tracked as 100755"
    local mode
    mode=$(git ls-files --stage bin/kafka-cli | awk '{print $1}')
    if [[ -z "$mode" ]]; then
        echo "::error::bin/kafka-cli is not tracked in git"
        return 1
    fi
    if [[ "$mode" != "100755" ]]; then
        echo "::error::bin/kafka-cli must be tracked as 100755 (got: $mode)"
        return 1
    fi
}

check_smoke() {
    step "smoke test (--help, --version)"
    bash bin/kafka-cli --help > /dev/null
    bash bin/kafka-cli --version
}

check_yaml() {
    step "workflow YAML validity"
    if ! command -v python3 >/dev/null 2>&1; then
        echo "::error::python3 not found — needed to validate workflow YAML"
        return 1
    fi
    if ! python3 -c 'import yaml' 2>/dev/null; then
        echo "::error::PyYAML not available — install with 'pip install pyyaml'"
        return 1
    fi
    python3 -c '
import yaml, pathlib
for p in sorted(pathlib.Path(".github/workflows").glob("*.yml")):
    yaml.safe_load(p.read_text())
    print(f"  ok: {p}")
'
}

check_gitleaks() {
    step "gitleaks secret scan"
    if in_ci; then
        # Download a pinned binary so the scan is reproducible.
        local version=8.21.2
        curl -fsSL -o /tmp/gitleaks.tar.gz \
            "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_x64.tar.gz"
        tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks
        /tmp/gitleaks detect --no-banner --exit-code=1
    elif command -v gitleaks >/dev/null 2>&1; then
        gitleaks detect --no-banner --exit-code=1
    else
        echo "  (skipping locally — gitleaks not on PATH; CI will run it)"
    fi
}

run_all() {
    check_syntax
    check_shellcheck
    check_whitespace
    check_crlf
    check_exec_bit
    check_smoke
    check_yaml
    check_gitleaks
    printf '\nAll checks passed.\n'
}

usage() {
    cat <<'EOF'
test/ci.sh — PR-time validation. Runs locally AND in CI.

Usage:
  ./test/ci.sh              run every check (default)
  ./test/ci.sh <check>      run one of:
                                syntax shellcheck whitespace crlf
                                exec-bit smoke yaml gitleaks
  ./test/ci.sh --help       show this help

In CI (CI=true), gitleaks downloads its own binary. Locally, the script
uses any system gitleaks or skips with a notice.
EOF
}

case "${1:-all}" in
    syntax)     check_syntax ;;
    shellcheck) check_shellcheck ;;
    whitespace) check_whitespace ;;
    crlf)       check_crlf ;;
    exec-bit)   check_exec_bit ;;
    smoke)      check_smoke ;;
    yaml)       check_yaml ;;
    gitleaks)   check_gitleaks ;;
    all)        run_all ;;
    -h|--help)  usage ;;
    *)          echo "unknown check: $1 (try --help)" >&2; exit 2 ;;
esac
