#!/bin/bash
# SleepLab Agent Query Helper
# Usage: ./query.sh <endpoint> [query-params]
#
# Examples:
#   ./query.sh sleep days=7
#   ./query.sh sleep/2026-02-27
#   ./query.sh sleep/range from=2026-02-20&to=2026-02-27
#   ./query.sh sleep/stats days=14
#   ./query.sh events days=7

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env file not found at $ENV_FILE"
  echo "Please set up your SleepLab connection first."
  exit 1
fi

source "$ENV_FILE"

if [ -z "${SLEEPLAB_API_KEY:-}" ] || [ -z "${SLEEPLAB_API_URL:-}" ]; then
  echo "ERROR: SLEEPLAB_API_KEY and SLEEPLAB_API_URL must be set in .env"
  exit 1
fi

ENDPOINT="${1:?Usage: query.sh <endpoint> [query-params]}"
PARAMS="${2:-}"

URL="$SLEEPLAB_API_URL/v1/data/$ENDPOINT"
if [ -n "$PARAMS" ]; then
  URL="$URL?$PARAMS"
fi

curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$URL"
