#!/usr/bin/env bash
# =====================================================================
# Portfolio 5: PostgreSQL streaming replication on macOS (Homebrew)
# I run a primary (port 5432) and a hot standby replica (port 5433) on one Mac.
# The same mechanism sits underneath managed cloud services such as Amazon RDS
# read replicas and Google Cloud SQL replicas.
#
# Run from the repo root or this folder, with Homebrew PostgreSQL 16 running:
#     bash 01_replication_demo_mac.sh
# Optional overrides: PRIMARY_PORT, REPLICA_PORT, REPLICA_DIR, PGBIN, DB
#
# Docs consulted:
#   PostgreSQL 16, High Availability, Load Balancing, and Replication
#   https://www.postgresql.org/docs/16/high-availability.html
#   PostgreSQL 16, pg_basebackup
#   https://www.postgresql.org/docs/16/app-pgbasebackup.html
# =====================================================================
set -euo pipefail

PRIMARY_PORT="${PRIMARY_PORT:-5432}"
REPLICA_PORT="${REPLICA_PORT:-5433}"
DB="${DB:-atelier_db}"
REPLICA_DIR="${REPLICA_DIR:-$HOME/pg_replica_demo}"
if [ -z "${PGBIN:-}" ]; then
  if command -v brew >/dev/null 2>&1 && brew --prefix postgresql@16 >/dev/null 2>&1; then
    PGBIN="$(brew --prefix postgresql@16)/bin"
  else
    PGBIN="$(pg_config --bindir)"
  fi
fi
P="$PGBIN/psql -X -h 127.0.0.1"          # psql over TCP, no password needed on a default Homebrew install

cleanup() {   # always stop and remove the demo replica, even if a step fails
  if [ -d "$REPLICA_DIR" ]; then
    "$PGBIN/pg_ctl" -D "$REPLICA_DIR" -m fast stop >/dev/null 2>&1 || true
    rm -rf "$REPLICA_DIR"
  fi
}
trap cleanup EXIT

echo "### 0. Checks"
"$PGBIN/pg_isready" -h 127.0.0.1 -p "$PRIMARY_PORT"
echo "wal_level on the primary: $($P -At -p "$PRIMARY_PORT" -d postgres -c 'SHOW wal_level')"

echo "### 1. Prepare the primary: a dedicated replication role (least privilege)"
$P -q -p "$PRIMARY_PORT" -d postgres \
   -c "DROP ROLE IF EXISTS replicator" \
   -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl_demo_pw'"

echo "### 2. Take a base backup of the primary into a new data directory (-R writes the standby settings)"
rm -rf "$REPLICA_DIR"
PGPASSWORD=repl_demo_pw "$PGBIN/pg_basebackup" -h 127.0.0.1 -p "$PRIMARY_PORT" -U replicator \
   -D "$REPLICA_DIR" -R -X stream
chmod 700 "$REPLICA_DIR"

echo "### 3. Start the replica on port $REPLICA_PORT (hot standby, so read only queries are allowed)"
"$PGBIN/pg_ctl" -D "$REPLICA_DIR" -o "-p $REPLICA_PORT" -l "$REPLICA_DIR/replica.log" -w start

echo "### 4. Replication status as seen from the PRIMARY"
sleep 1
$P -p "$PRIMARY_PORT" -d postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication"

echo "### 5. Write on the primary, read from the replica"
$P -q -p "$PRIMARY_PORT" -d "$DB" -c "UPDATE variants SET stock_qty = 77 WHERE variant_id = 20"
sleep 1
echo "primary :"; $P -At -p "$PRIMARY_PORT" -d "$DB" -c "SELECT stock_qty FROM variants WHERE variant_id = 20"
echo "replica :"; $P -At -p "$REPLICA_PORT" -d "$DB" -c "SELECT stock_qty FROM variants WHERE variant_id = 20"

echo "### 6. The replica is read only (writes must go to the primary)"
$P -p "$REPLICA_PORT" -d "$DB" -c "UPDATE variants SET stock_qty = 1 WHERE variant_id = 20" || echo "(expected error above)"
echo "pg_is_in_recovery on the replica: $($P -At -p "$REPLICA_PORT" -d "$DB" -c 'SELECT pg_is_in_recovery()')"

echo "### 7. Replication lag: insert 20,000 rows on the primary, then time how long the replica takes to show them all"
python3 - "$PRIMARY_PORT" "$REPLICA_PORT" "$DB" "$PGBIN" <<'PY'
import subprocess, sys, time
prim, repl, db, bindir = sys.argv[1:5]
def psql(port, sql, quiet=False):
    cmd = [f"{bindir}/psql", "-X", "-At", "-h", "127.0.0.1", "-p", port, "-d", db, "-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()
psql(prim, "DROP TABLE IF EXISTS lag_probe")
psql(prim, "CREATE TABLE lag_probe(id bigserial primary key, ts timestamptz default now())")
time.sleep(1)                                     # let the CREATE TABLE reach the replica first
t0 = time.perf_counter()
psql(prim, "INSERT INTO lag_probe(ts) SELECT now() FROM generate_series(1,20000)")
t1 = time.perf_counter()
print(f"primary commit finished after {(t1 - t0) * 1000:.0f} ms")
for _ in range(200):
    n = psql(repl, "SELECT count(*) FROM lag_probe")
    if n == "20000":
        print(f"replica showed all 20000 rows {(time.perf_counter() - t1) * 1000:.0f} ms after the primary commit "
              f"(includes one psql start-up per poll)")
        break
    print(f"replica currently shows {n} rows (eventual consistency window)")
psql(prim, "DROP TABLE lag_probe")
PY

echo "### 8. Fail-over: promote the replica to be the new primary"
"$PGBIN/pg_ctl" -D "$REPLICA_DIR" promote -w
sleep 1
echo "replica still in recovery? $($P -At -p "$REPLICA_PORT" -d "$DB" -c 'SELECT pg_is_in_recovery()')"
$P -q -p "$REPLICA_PORT" -d "$DB" -c "UPDATE variants SET stock_qty = 78 WHERE variant_id = 20" && echo "write accepted on promoted node"

echo "### 9. Clean up the demo replica and restore the value I changed"
cleanup
$P -q -p "$PRIMARY_PORT" -d "$DB" -c "UPDATE variants SET stock_qty = 77 WHERE variant_id = 20"
$P -q -p "$PRIMARY_PORT" -d postgres -c "DROP ROLE IF EXISTS replicator"
echo "done"
