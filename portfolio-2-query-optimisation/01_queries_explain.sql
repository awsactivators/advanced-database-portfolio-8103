-- =====================================================================
-- Portfolio 2, Five business queries, each wrapped in EXPLAIN (ANALYZE, BUFFERS).
-- This same file is run TWICE: before and after 02_indexes.sql, so the two
-- evidence logs can be compared side by side.
-- Fixed dates are used (not now()) so results are repeatable.
-- =====================================================================
\pset pager off
SET max_parallel_workers_per_gather = 0;   -- keeps plans simple and comparable for the report

\echo '### Q1  Order history for one client (look-up by e-mail, then by customer_id)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_id, o.order_date, o.status, o.total_amount
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE c.email = 'client4242@example.com'
ORDER BY o.order_date DESC;

\echo '### Q2  Monthly revenue by shipping country, last 12 months, settled orders only'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('month', order_date) AS month,
       shipping_country,
       sum(total_amount)               AS revenue
FROM orders
WHERE order_date >= timestamptz '2025-10-01'
  AND status IN ('paid','in_production','shipped','delivered')
GROUP BY 1, 2
ORDER BY 1, revenue DESC;

\echo '### Q3  Ten best-selling products (by revenue) in collection "AW 2025"'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.sku, p.product_name, sum(oi.quantity * oi.unit_price) AS revenue
FROM collections c
JOIN products    p  ON p.collection_id = c.collection_id
JOIN variants    v  ON v.product_id    = p.product_id
JOIN order_items oi ON oi.variant_id   = v.variant_id
WHERE c.collection_name = 'AW 2025'
GROUP BY p.sku, p.product_name
ORDER BY revenue DESC
LIMIT 10;

\echo '### Q4  Top 3 spenders in each shipping country (window function)'
EXPLAIN (ANALYZE, BUFFERS)
WITH spend AS (
    SELECT o.shipping_country, o.customer_id, sum(o.total_amount) AS total_spend
    FROM orders o
    WHERE o.status IN ('paid','in_production','shipped','delivered')
    GROUP BY o.shipping_country, o.customer_id
), ranked AS (
    SELECT *, rank() OVER (PARTITION BY shipping_country ORDER BY total_spend DESC) AS rnk
    FROM spend
)
SELECT shipping_country, customer_id, total_spend, rnk
FROM ranked WHERE rnk <= 3
ORDER BY shipping_country, rnk;

\echo '### Q5  Stale pending orders (pending for more than 30 days) needing follow-up'
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'pending'
  AND order_date < timestamptz '2026-08-31'
ORDER BY order_date
LIMIT 50;
