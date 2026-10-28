#!/usr/bin/env bash
# Copies wardround into a running Oracle Free container, grants the app
# user what wardround needs and installs the schema. ci.sh and bench.sh
# start with this; the container is the one ci.sh describes.
set -euo pipefail

RUNTIME=${RUNTIME:-podman}
CONTAINER=${CONTAINER:-oracledb}
SYS_PASSWORD=${SYS_PASSWORD:-wardround}
APP_USER=${APP_USER:-wardround}
APP_PASSWORD=${APP_PASSWORD:-wardround}
DB=//localhost/FREEPDB1

cd "$(dirname "$0")/.."

# Runs sqlplus in the container, in directory $1, as $2, on the rest.
# $login is left unquoted so "as sysdba" is its own words. Scripts get
# </dev/null so sqlplus exits when they end.
sql() {
  local dir=$1 login=$2
  shift 2
  "$RUNTIME" exec -i -w "$dir" "$CONTAINER" sqlplus -s -L $login "$@"
}

echo "== Copying wardround into the container"
"$RUNTIME" exec "$CONTAINER" rm -rf /tmp/wardround
"$RUNTIME" cp . "$CONTAINER:/tmp/wardround"

echo "== Granting $APP_USER what wardround needs"
sql /tmp "sys/$SYS_PASSWORD@$DB as sysdba" <<SQL
whenever sqlerror exit failure
grant create session, create table, create view, create procedure to $APP_USER;
alter user $APP_USER quota unlimited on users;
exit
SQL

echo "== Installing wardround"
sql /tmp/wardround "$APP_USER/$APP_PASSWORD@$DB" @install.sql </dev/null
