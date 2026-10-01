-- =====================================================================
-- Portfolio 2, Indexing strategy, chosen from reading the "before" plans.
-- PostgreSQL does NOT create indexes on foreign-key columns automatically
-- (only on PRIMARY KEY / UNIQUE), so FK join columns are indexed by hand.
-- =====================================================================

-- Q1: orders of a given client (FK column, high selectivity)
CREATE INDEX idx_orders_customer_date ON orders (customer_id, order_date DESC);

-- Q2 / Q4: date-range scans on settled orders. INCLUDE lets PostgreSQL answer
-- from the index alone (index-only scan) without visiting the table heap.
CREATE INDEX idx_orders_date_settled ON orders (order_date)
    INCLUDE (shipping_country, total_amount)
    WHERE status IN ('paid','in_production','shipped','delivered');

-- Q3: join path collections -> products -> variants -> order_items
CREATE INDEX idx_products_collection  ON products (collection_id);
CREATE INDEX idx_order_items_variant  ON order_items (variant_id);

-- Q5: small partial index, only 'pending' rows are indexed
CREATE INDEX idx_orders_pending_date ON orders (order_date) WHERE status = 'pending';

ANALYZE;
