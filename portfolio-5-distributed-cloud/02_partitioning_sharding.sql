-- =====================================================================
-- Portfolio 5, Horizontal partitioning: the single-node building block of sharding.
-- In a sharded cloud database (Spanner, CockroachDB, Citus) each partition/"shard"
-- lives on a different node; here all partitions sit on one server, which is enough to
-- demonstrate routing, pruning and data distribution.
-- PostgreSQL 16 docs: https://www.postgresql.org/docs/16/ddl-partitioning.html
-- =====================================================================
\pset pager off
SET max_parallel_workers_per_gather = 0;

-- ---------- A. RANGE partitioning by order date (archive old years, prune queries)
DROP TABLE IF EXISTS orders_by_year CASCADE;
CREATE TABLE orders_by_year (
    order_id         BIGINT NOT NULL,
    customer_id      BIGINT NOT NULL,
    order_date       TIMESTAMPTZ NOT NULL,
    status           TEXT NOT NULL,
    shipping_country CHAR(2) NOT NULL,
    total_amount     NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (order_id, order_date)          -- the partition key must be part of the PK
) PARTITION BY RANGE (order_date);

CREATE TABLE orders_2024 PARTITION OF orders_by_year FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');
CREATE TABLE orders_2025 PARTITION OF orders_by_year FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
CREATE TABLE orders_2026 PARTITION OF orders_by_year FOR VALUES FROM ('2026-01-01') TO ('2027-01-01');

INSERT INTO orders_by_year
SELECT order_id, customer_id, order_date, status, shipping_country, total_amount FROM orders;
ANALYZE orders_by_year;

\echo '### A1  Rows per partition (tableoid tells us which partition stores each row)'
SELECT tableoid::regclass AS partition, count(*) FROM orders_by_year GROUP BY 1 ORDER BY 1;

\echo '### A2  Partition pruning: a 2025 query should scan ONLY orders_2025'
EXPLAIN (COSTS OFF)
SELECT sum(total_amount) FROM orders_by_year
WHERE order_date >= '2025-03-01' AND order_date < '2025-04-01';

\echo '### A3  Without a date filter every partition must be scanned'
EXPLAIN (COSTS OFF) SELECT count(*) FROM orders_by_year WHERE status = 'pending';

-- ---------- B. HASH partitioning by customer: spreads load evenly like shards
DROP TABLE IF EXISTS orders_sharded CASCADE;
CREATE TABLE orders_sharded (
    order_id     BIGINT NOT NULL,
    customer_id  BIGINT NOT NULL,
    order_date   TIMESTAMPTZ NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    PRIMARY KEY (customer_id, order_id)
) PARTITION BY HASH (customer_id);

CREATE TABLE orders_shard_0 PARTITION OF orders_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE orders_shard_1 PARTITION OF orders_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE orders_shard_2 PARTITION OF orders_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE orders_shard_3 PARTITION OF orders_sharded FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO orders_sharded SELECT order_id, customer_id, order_date, total_amount FROM orders;
ANALYZE orders_sharded;

\echo '### B1  Even distribution across the 4 "shards"'
SELECT tableoid::regclass AS shard, count(*) AS orders,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM orders_sharded GROUP BY 1 ORDER BY 1;

\echo '### B2  A query that includes the shard key is routed to ONE shard'
EXPLAIN (COSTS OFF) SELECT * FROM orders_sharded WHERE customer_id = 4242;

\echo '### B3  A query WITHOUT the shard key must fan out to all shards (scatter-gather)'
EXPLAIN (COSTS OFF) SELECT count(*) FROM orders_sharded WHERE total_amount > 5000;

-- tidy up so the demo can be re-run
DROP TABLE orders_by_year, orders_sharded CASCADE;
