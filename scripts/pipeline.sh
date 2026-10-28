#!/usr/bin/env bash
# The whole path a hospital's data takes: generates 45 days of feed, sends
# it over MLLP to the listener, applies it, and runs the reports for
# March 2026. Needs wardround installed (pip install -e .) and the schema
# at WARDROUND_DSN.
set -euo pipefail

export WARDROUND_DSN=${WARDROUND_DSN:-localhost/FREEPDB1}
PORT=${PORT:-2575}
cd "$(dirname "$0")/.."
mkdir -p build

echo "== Generating the feed"
wardround generate --out build/feed.hl7

echo "== Sending it over MLLP"
wardround listen --port "$PORT" > build/listener.log 2>&1 &
listener=$!
trap 'kill $listener 2>/dev/null || true' EXIT
for _ in $(seq 50); do
  grep -q listening build/listener.log && break
  sleep 0.2
done
wardround send build/feed.hl7 --port "$PORT"

echo "== Applying it"
wardround process

echo "== Reports for March 2026"
wardround report --from 2026-03-01 --to 2026-04-01 | tee build/reports.txt
wardround report --from 2026-03-01 --to 2026-04-01 --format html --out build/reports.html

echo "== Mapping the codes the feed sent that nobody had mapped, and reprocessing"
wardround report --from 2026-02-15 --to 2026-04-01 --only interface_errors
wardround map 72 LAB 2093-3 CHOL --display Cholesterol
wardround map 220 REG 4WEST 4W
wardround reprocess
wardround report --from 2026-02-15 --to 2026-04-01 --only interface_errors
