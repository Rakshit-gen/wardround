#!/usr/bin/env bash
# Installs utPLSQL and wardround into a running Oracle Free container and
# runs the tests. CI starts the container with gvenzl/setup-oracle-free;
# locally, something like
#   docker run -d --name oracledb -p 1521:1521 -e ORACLE_PASSWORD=wardround \
#     -e APP_USER=wardround -e APP_USER_PASSWORD=wardround gvenzl/oracle-free:23
#   RUNTIME=docker ./scripts/ci.sh
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-wardround}
APP_USER=${APP_USER:-wardround}
APP_PASSWORD=${APP_PASSWORD:-wardround}
UTPLSQL_VERSION=3.2.2
UTPLSQL_SHA256=02bb981528e6f97f92b7faaced01ae56da91fe420aacf96624c5c12f4d4f1c5c
DB=//localhost/FREEPDB1

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Runs sqlplus in the container, in directory $1, as $2, on the rest.
# $login is left unquoted so "as sysdba" is its own words. Scripts get
# </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L $login "$@"
}

echo "== Copying files into the container"
curl -fsSL -o "$work/utPLSQL.tar.gz" \
  "https://github.com/utPLSQL/utPLSQL/releases/download/v$UTPLSQL_VERSION/utPLSQL.tar.gz"
echo "$UTPLSQL_SHA256  $work/utPLSQL.tar.gz" | sha256sum -c -
tar -xzf "$work/utPLSQL.tar.gz" -C "$work"
"$RUNTIME" exec "$CONTAINER" rm -rf /tmp/wardround /tmp/utPLSQL
"$RUNTIME" cp "$work/utPLSQL" "$CONTAINER:/tmp/utPLSQL"
"$RUNTIME" cp . "$CONTAINER:/tmp/wardround"

echo "== Installing utPLSQL $UTPLSQL_VERSION"
sql /tmp/utPLSQL/source "sys/$SYS_PASSWORD@$DB as sysdba" @install_headless.sql UT3 "$SYS_PASSWORD" users </dev/null

echo "== Granting $APP_USER what wardround needs"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
whenever sqlerror exit failure
grant create session, create table, create view, create procedure to $APP_USER;
alter user $APP_USER quota unlimited on users;
exit
SQL

app="$APP_USER/$APP_PASSWORD@$DB"

echo "== Installing wardround, removing it, and installing it again"
sql /tmp/wardround "$app" @install.sql </dev/null
sql /tmp/wardround "$app" @uninstall.sql </dev/null
sql /tmp/wardround "$app" @install.sql </dev/null
