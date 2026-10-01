#!/usr/bin/env bash
set -euo pipefail

test_type="${1:-load}"
if (( $# > 0 )); then
  shift
fi

case "$test_type" in
  load|stress|spike) ;;
  *)
    printf 'Usage: %s [load|stress|spike] [read|write] [k6 run flags]\n' "$0" >&2
    exit 2
    ;;
esac

operation=""
case "${1:-}" in
  read|write)
    operation="$1"
    shift
    ;;
  ""|-*) ;;
  *)
    printf 'Operation must be read or write\n' >&2
    exit 2
    ;;
esac

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

# Keep the existing METHOD setting as the default when no operation is supplied.
if [[ -z "$operation" ]]; then
  case "${METHOD:-GET}" in
    GET) operation=read ;;
    POST) operation=write ;;
    *) printf 'METHOD must be GET or POST\n' >&2; exit 2 ;;
  esac
fi

base_url="${BASE_URL:-http://localhost:8080}"
base_url="${base_url%/}"
case "$operation" in
  read)
    request_method=GET
    request_url="${READ_URL:-${URL:-$base_url/db}}"
    ;;
  write)
    request_method=POST
    request_url="${WRITE_URL:-$base_url/dp}"
    ;;
esac

# Dashboard settings must be exported before k6 starts.
export K6_WEB_DASHBOARD=true
export K6_WEB_DASHBOARD_PERIOD="${K6_WEB_DASHBOARD_PERIOD:-1s}"
export K6_WEB_DASHBOARD_EXPORT="${test_type}-${operation}.html"

# Apply the selected operation after extra flags so the report matches the test.
exec k6 run "$@" -e "TEST_TYPE=$test_type" -e "METHOD=$request_method" \
  -e "URL=$request_url" test.js
