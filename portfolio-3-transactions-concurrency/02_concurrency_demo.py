#!/usr/bin/env python3
"""
Portfolio 3, Concurrency demonstrations on the Atelier Verane database.

Four experiments, each using two real database sessions running in parallel threads:
  A. Lost update / overselling  (naive read-modify-write at READ COMMITTED)
  B. Fix 1: pessimistic locking (SELECT ... FOR UPDATE)
  C. Fix 2: SERIALIZABLE isolation + application retry
  D. Deadlock (opposite lock order) and its fix (consistent lock order)

Usage:
    pip install psycopg2-binary
    export PGDSN="dbname=atelier_db user=postgres password=YOURPASSWORD host=localhost"
    python3 02_concurrency_demo.py

Documentation consulted: PostgreSQL 16 manual, chapters "Transaction Isolation"
(https://www.postgresql.org/docs/16/transaction-iso.html) and "Explicit Locking"
(https://www.postgresql.org/docs/16/explicit-locking.html).
"""
import os
import threading
import time

import psycopg2
from psycopg2 import errors
from psycopg2.extensions import (ISOLATION_LEVEL_READ_COMMITTED,
                                 ISOLATION_LEVEL_SERIALIZABLE)

DSN = os.environ.get("PGDSN", "dbname=atelier_db user=postgres password=postgres host=localhost")
LAST_ITEM_VARIANT = 10          # the piece everybody wants: exactly 1 left in stock
VARIANT_A, VARIANT_B = 11, 12   # used for the deadlock experiment


def connect(level=ISOLATION_LEVEL_READ_COMMITTED):
    conn = psycopg2.connect(DSN)
    conn.set_isolation_level(level)
    return conn


def reset_stock(variant_id, qty):
    with connect() as c, c.cursor() as cur:
        cur.execute("UPDATE variants SET stock_qty = %s WHERE variant_id = %s", (qty, variant_id))
        cur.execute("DELETE FROM stock_movements WHERE variant_id = %s", (variant_id,))


def stock_of(variant_id):
    with connect() as c, c.cursor() as cur:
        cur.execute("SELECT stock_qty FROM variants WHERE variant_id = %s", (variant_id,))
        return cur.fetchone()[0]


def run_two(target):
    """Run two buyers in parallel; return list of result strings."""
    barrier = threading.Barrier(2)
    results = [None, None]

    def worker(i):
        results[i] = target(i, barrier)

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(2)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    return results


# ---------------------------------------------------------------- A
def naive_buyer(i, barrier):
    conn = connect()
    cur = conn.cursor()
    cur.execute("SELECT stock_qty FROM variants WHERE variant_id = %s", (LAST_ITEM_VARIANT,))
    seen = cur.fetchone()[0]
    barrier.wait()                       # both buyers have now read stock = 1
    if seen >= 1:
        # application computes the NEW absolute value from what it read earlier (the bug)
        cur.execute("UPDATE variants SET stock_qty = %s WHERE variant_id = %s",
                    (seen - 1, LAST_ITEM_VARIANT))
        cur.execute("INSERT INTO stock_movements (variant_id, delta, reason) VALUES (%s,-1,%s)",
                    (LAST_ITEM_VARIANT, f"naive buyer {i}"))
        conn.commit()
        return f"buyer {i}: ORDER ACCEPTED"
    conn.rollback()
    return f"buyer {i}: rejected (sold out)"


# ---------------------------------------------------------------- B
def locking_buyer(i, barrier):
    conn = connect()
    cur = conn.cursor()
    barrier.wait()
    cur.execute("SELECT stock_qty FROM variants WHERE variant_id = %s FOR UPDATE", (LAST_ITEM_VARIANT,))
    seen = cur.fetchone()[0]             # the second buyer blocks here until the first commits
    time.sleep(0.3)                      # simulate processing while holding the lock
    if seen >= 1:
        cur.execute("UPDATE variants SET stock_qty = stock_qty - 1 WHERE variant_id = %s", (LAST_ITEM_VARIANT,))
        cur.execute("INSERT INTO stock_movements (variant_id, delta, reason) VALUES (%s,-1,%s)",
                    (LAST_ITEM_VARIANT, f"locking buyer {i}"))
        conn.commit()
        return f"buyer {i}: ORDER ACCEPTED"
    conn.rollback()
    return f"buyer {i}: rejected (sold out), saw stock {seen}"


# ---------------------------------------------------------------- C
def serializable_buyer(i, barrier):
    for attempt in (1, 2):
        conn = connect(ISOLATION_LEVEL_SERIALIZABLE)
        cur = conn.cursor()
        try:
            cur.execute("SELECT stock_qty FROM variants WHERE variant_id = %s", (LAST_ITEM_VARIANT,))
            seen = cur.fetchone()[0]
            if attempt == 1:
                barrier.wait()
            if seen < 1:
                conn.rollback()
                return f"buyer {i}: rejected (sold out) on attempt {attempt}"
            cur.execute("UPDATE variants SET stock_qty = %s WHERE variant_id = %s",
                        (seen - 1, LAST_ITEM_VARIANT))
            conn.commit()
            return f"buyer {i}: ORDER ACCEPTED on attempt {attempt}"
        except errors.SerializationFailure as e:
            conn.rollback()
            print(f"   buyer {i}: SerializationFailure ({e.pgcode}) -> retrying")
        finally:
            conn.close()
    return f"buyer {i}: gave up"


# ---------------------------------------------------------------- D
def lock_pair(i, barrier, first, second, label, use_barrier=True):
    conn = connect()
    cur = conn.cursor()
    try:
        cur.execute("SELECT 1 FROM variants WHERE variant_id = %s FOR UPDATE", (first,))
        if use_barrier:
            barrier.wait()               # each session now holds one lock and wants the other
        else:
            time.sleep(0.3)              # same order: the 2nd session simply waits on the 1st lock
        cur.execute("SELECT 1 FROM variants WHERE variant_id = %s FOR UPDATE", (second,))
        conn.commit()
        return f"session {i} ({label}): committed"
    except errors.DeadlockDetected as e:
        conn.rollback()
        return f"session {i} ({label}): ABORTED by deadlock detector ({e.pgcode})"


def main():
    print("=" * 70)
    print("A. NAIVE read-modify-write at READ COMMITTED (expected: overselling)")
    reset_stock(LAST_ITEM_VARIANT, 1)
    for line in run_two(naive_buyer):
        print("  ", line)
    print(f"   final stock = {stock_of(LAST_ITEM_VARIANT)}  (1 item existed, 2 orders accepted -> LOST UPDATE)")

    print("=" * 70)
    print("B. FIX 1, SELECT ... FOR UPDATE (second buyer waits, then sees stock 0)")
    reset_stock(LAST_ITEM_VARIANT, 1)
    for line in run_two(locking_buyer):
        print("  ", line)
    print(f"   final stock = {stock_of(LAST_ITEM_VARIANT)}")

    print("=" * 70)
    print("C. FIX 2, SERIALIZABLE isolation with retry")
    reset_stock(LAST_ITEM_VARIANT, 1)
    for line in run_two(serializable_buyer):
        print("  ", line)
    print(f"   final stock = {stock_of(LAST_ITEM_VARIANT)}")

    print("=" * 70)
    print("D1. DEADLOCK, sessions lock variants in opposite order")
    for v in (VARIANT_A, VARIANT_B):
        reset_stock(v, 5)
    orders = {0: (VARIANT_A, VARIANT_B), 1: (VARIANT_B, VARIANT_A)}
    for line in run_two(lambda i, b: lock_pair(i, b, *orders[i], label="opposite order")):
        print("  ", line)

    print("D2. FIX, both sessions lock in the SAME (ascending) order")
    for line in run_two(lambda i, b: lock_pair(i, b, VARIANT_A, VARIANT_B, label="same order", use_barrier=False)):
        print("  ", line)
    print("=" * 70)


if __name__ == "__main__":
    main()
