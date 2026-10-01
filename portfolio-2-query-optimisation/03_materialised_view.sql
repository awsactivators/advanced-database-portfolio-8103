-- =====================================================================
-- Portfolio 2, Materialised view for the dashboard workload (Q4 showed that
-- indexes cannot help a query that must aggregate every settled order).
-- A materialised view stores the pre-computed aggregate physically (course
-- slides S2_04) and is refreshed on a schedule instead of on every read.
-- =====================================================================
\pset pager off
SET max_parallel_workers_per_gather = 0;

DROP MATERIALIZED VIEW IF EXISTS mv_customer_spend;
CREATE MATERIALIZED VIEW mv_customer_spend AS
SELECT shipping_country,
       customer_id,
       count(*)          AS settled_orders,
       sum(total_amount) AS total_spend
FROM orders
WHERE status IN ('paid','in_production','shipped','delivered')
GROUP BY shipping_country, customer_id
WITH DATA;

-- A UNIQUE index is what allows REFRESH ... CONCURRENTLY (readers are not blocked)
CREATE UNIQUE INDEX uq_mv_customer_spend ON mv_customer_spend (shipping_country, customer_id);
CREATE INDEX idx_mv_customer_spend_rank ON mv_customer_spend (shipping_country, total_spend DESC);
ANALYZE mv_customer_spend;

\echo '### Q4 re-written to read the materialised view'
EXPLAIN (ANALYZE, BUFFERS)
SELECT shipping_country, customer_id, total_spend, rnk
FROM (
    SELECT *, rank() OVER (PARTITION BY shipping_country ORDER BY total_spend DESC) AS rnk
    FROM mv_customer_spend
) r
WHERE rnk <= 3
ORDER BY shipping_country, rnk;

\echo '### Staleness demonstration: the view is a snapshot until it is refreshed'
-- pick one client that has at least one 'paid' order
SELECT m.shipping_country AS c_country, m.customer_id AS c_id
FROM mv_customer_spend m
JOIN orders o ON o.customer_id = m.customer_id AND o.shipping_country = m.shipping_country AND o.status = 'paid'
ORDER BY m.customer_id LIMIT 1 \gset

SELECT total_spend AS view_spend_before FROM mv_customer_spend
WHERE shipping_country = :'c_country' AND customer_id = :c_id;

UPDATE orders SET total_amount = total_amount + 1000
WHERE order_id = (SELECT min(order_id) FROM orders
                  WHERE customer_id = :c_id AND shipping_country = :'c_country' AND status = 'paid');

SELECT (SELECT sum(total_amount) FROM orders
        WHERE customer_id = :c_id AND shipping_country = :'c_country'
          AND status IN ('paid','in_production','shipped','delivered')) AS live_spend_after_update,
       (SELECT total_spend FROM mv_customer_spend
        WHERE shipping_country = :'c_country' AND customer_id = :c_id)   AS stale_view_spend;

\echo '### Refresh without blocking readers (CONCURRENTLY needs the UNIQUE index above)'
\timing on
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_customer_spend;
\timing off

SELECT total_spend AS view_spend_after_refresh FROM mv_customer_spend
WHERE shipping_country = :'c_country' AND customer_id = :c_id;
