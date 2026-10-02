#!/usr/bin/env python3
"""
Portfolio 4, Key-value model in Redis for Atelier Verane.

Three access patterns that do NOT need SQL:
  1. Shopping cart      -> Redis HASH   cart:<customer_id>   (+ TTL so abandoned carts expire)
  2. Login session      -> Redis STRING session:<token>      (+ TTL)
  3. Product-page cache -> cache-aside  price:<sku>          (PostgreSQL stays the source of truth)
  4. Trending products  -> Redis SORTED SET trending:day     (ZINCRBY / ZREVRANGE)

Docs consulted: Redis commands reference https://redis.io/docs/latest/commands/  (HSET, EXPIRE, ZINCRBY)
Course link: slides S2_04 "Caching Strategies" (distributed cache, invalidation challenge).

    pip install redis psycopg2-binary
    python3 04_redis_keyvalue_demo.py
"""
import os
import statistics
import time

import psycopg2
import redis

r = redis.Redis(host=os.environ.get("REDIS_HOST", "localhost"), port=6379, decode_responses=True)
DSN = os.environ.get("PGDSN", "dbname=atelier_db user=postgres password=postgres host=localhost")
pg = psycopg2.connect(DSN)
pg.autocommit = True

r.flushdb()
print("1. CART (hash with TTL)")
r.hset("cart:1001", mapping={"AV-00007:M:Noir": 1, "AV-00012:S:Ivory": 2})
r.hincrby("cart:1001", "AV-00007:M:Noir", 1)       # atomic increment, no read-modify-write race
r.expire("cart:1001", 60 * 60 * 24)                # abandoned carts vanish after 24 h
print("   cart:", r.hgetall("cart:1001"), "| TTL seconds:", r.ttl("cart:1001"))

print("2. SESSION (string with short TTL)")
r.set("session:tok_9f2c", "customer:1001", ex=1)
print("   exists now:", bool(r.exists("session:tok_9f2c")))
time.sleep(1.2)
print("   exists after TTL:", bool(r.exists("session:tok_9f2c")), "(expired automatically)")

print("3. CACHE-ASIDE price look-up: PostgreSQL vs Redis")


def price_from_pg(sku):
    with pg.cursor() as cur:
        cur.execute("SELECT base_price FROM products WHERE sku = %s", (sku,))
        return float(cur.fetchone()[0])


def price_cached(sku):
    key = f"price:{sku}"
    hit = r.get(key)
    if hit is not None:
        return float(hit), "HIT"
    value = price_from_pg(sku)
    r.set(key, value, ex=300)                      # 5-minute TTL bounds staleness
    return value, "MISS"


skus = [f"AV-{i:05d}" for i in range(1, 101)]
pg_times, hit_times = [], []
for _ in range(5):
    for s in skus:
        t = time.perf_counter(); price_from_pg(s); pg_times.append(time.perf_counter() - t)
for s in skus:
    price_cached(s)                               # warm the cache (all misses)
for _ in range(5):
    for s in skus:
        t = time.perf_counter(); price_cached(s); hit_times.append(time.perf_counter() - t)
print(f"   PostgreSQL median: {statistics.median(pg_times)*1000:.3f} ms   Redis HIT median: {statistics.median(hit_times)*1000:.3f} ms")
print("   (both measured through a Python client on the same machine, so absolute numbers are indicative only)")

print("   Invalidation: a price change must delete the cached copy, otherwise readers see stale data")
with pg.cursor() as cur:
    cur.execute("UPDATE products SET base_price = base_price + 10 WHERE sku = 'AV-00001' RETURNING base_price")
    new = float(cur.fetchone()[0])
print("   cached (stale):", r.get("price:AV-00001"), "| database:", new)
r.delete("price:AV-00001")
print("   after invalidation ->", price_cached("AV-00001"))
with pg.cursor() as cur:
    cur.execute("UPDATE products SET base_price = base_price - 10 WHERE sku = 'AV-00001'")   # restore data

print("4. TRENDING (sorted set)")
for sku, n in [("AV-00007", 5), ("AV-00012", 3), ("AV-00001", 8), ("AV-00099", 1)]:
    r.zincrby("trending:day", n, sku)
print("   top 3:", r.zrevrange("trending:day", 0, 2, withscores=True))
