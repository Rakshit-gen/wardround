#!/usr/bin/env bash
# Runs the whole path once for each feed size in $SIZES, given as ED
# visits a day:direct admissions a day, each on a freshly installed
# schema and an empty shared pool: generates 45 days, sends them over
# MLLP, applies them and prints the statements that took longest, times
# the March reports over 5 runs each, maps the unmapped codes and
# reprocesses. Needs install.sh run first and wardround installed.
#   SIZES="30:3 90:9" ./scripts/bench.sh
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-wardround}
APP_USER=${APP_USER:-wardround}
APP_PASSWORD=${APP_PASSWORD:-wardround}
SIZES=${SIZES:-30:3}
PORT=${PORT:-2575}
export WARDROUND_DSN=${WARDROUND_DSN:-localhost/FREEPDB1}

cd "$(dirname "$0")/.."
mkdir -p build

sql() {
  "$RUNTIME" exec -i -w /tmp/wardround "$CONTAINER" \
    sqlplus -s -L "$APP_USER/$APP_PASSWORD@//localhost/FREEPDB1" "$@" </dev/null
}

sys() {
  "$RUNTIME" exec -i "$CONTAINER" sqlplus -s -L "sys/$SYS_PASSWORD@//localhost/FREEPDB1" as sysdba
}

echo "== Where the benchmark runs"
echo "runner: $(nproc) CPUs, $(lscpu 2>/dev/null | sed -n 's/^Model name: *//p' | head -1), $(free -g 2>/dev/null | awk '/^Mem:/ { print $2 " GB" }') memory"
python --version

for size in $SIZES; do
  IFS=: read -r ed direct <<<"$size"
  echo "== $ed ED visits and $direct direct admissions a day"
  sql @uninstall.sql >/dev/null
  sql @install.sql >/dev/null
  echo "alter system flush shared_pool;" | sys >/dev/null

  TIMEFORMAT="generate took %R s"
  time wardround generate --ed-per-day "$ed" --direct-per-day "$direct" --out build/bench.hl7

  wardround listen --port "$PORT" > build/listener.log 2>&1 &
  listener=$!
  for _ in $(seq 50); do
    grep -q listening build/listener.log && break
    sleep 0.2
  done
  wardround send build/bench.hl7 --port "$PORT"
  kill $listener
  wait $listener 2>/dev/null || true

  wardround process
  echo "-- the statements that took longest to apply it"
  sys <<SQL
set linesize 250 pagesize 100 feedback off
column secs format 9990.00
column sql_text format a150
select executions, round(elapsed_time / 1e6, 2) as secs, substr(sql_text, 1, 150) as sql_text
  from v\$sql
 where parsing_schema_name = upper('$APP_USER')
 order by elapsed_time desc
 fetch first 6 rows only;
exit
SQL
  wardround report --from 2026-03-01 --to 2026-04-01 --timing --repeat 5 --out /dev/null

  wardround map 72 LAB 2093-3 CHOL --display Cholesterol >/dev/null
  wardround map 220 REG 4WEST 4W >/dev/null
  TIMEFORMAT="reprocess took %R s"
  time wardround reprocess
  wardround status | tee build/status.txt
  if awk '$1 ~ /^(NEW|HELD|ERROR)$/ && $2 > 0 { bad = 1 } END { exit !bad }' build/status.txt; then
    echo "messages left unapplied" >&2
    exit 1
  fi
done
