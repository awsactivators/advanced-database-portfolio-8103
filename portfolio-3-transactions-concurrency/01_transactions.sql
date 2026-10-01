-- =====================================================================
-- Portfolio 3, Transactions (ACID) for Atelier Verane
-- Run after Portfolio 1.   psql -d atelier_db -f 01_transactions.sql
-- Business rule: an order must (a) reserve stock, (b) record the order line,
-- (c) record the payment and (d) log the stock movement, all or nothing.
-- =====================================================================
\pset pager off

-- Fixtures so the examples are repeatable: a dedicated variant with known stock
UPDATE variants SET stock_qty = 3 WHERE variant_id = 1;
DELETE FROM stock_movements;

\echo '=== Example 1: successful transaction -> COMMIT (Atomicity + Durability)'
BEGIN;
    INSERT INTO orders (customer_id, status, shipping_country, total_amount)
    VALUES (1, 'paid', 'FR', 0) RETURNING order_id \gset
    INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
    SELECT :order_id, v.variant_id, 1, p.base_price
    FROM variants v JOIN products p USING (product_id) WHERE v.variant_id = 1;
    UPDATE variants SET stock_qty = stock_qty - 1 WHERE variant_id = 1;
    UPDATE orders SET total_amount = (SELECT sum(quantity*unit_price) FROM order_items WHERE order_id = :order_id)
        WHERE order_id = :order_id;
    INSERT INTO payments (order_id, amount, method, payment_status)
    SELECT order_id, total_amount, 'card', 'captured' FROM orders WHERE order_id = :order_id;
    INSERT INTO stock_movements (variant_id, delta, reason) VALUES (1, -1, 'sale order ' || :order_id);
COMMIT;
SELECT variant_id, stock_qty FROM variants WHERE variant_id = 1;

\echo '=== Example 2: business rule violated mid-way -> ROLLBACK (Atomicity + Consistency)'
\echo 'Trying to buy 5 items when only 2 remain; the CHECK (stock_qty >= 0) constraint rejects it.'
BEGIN;
    INSERT INTO orders (customer_id, status, shipping_country, total_amount)
    VALUES (1, 'paid', 'FR', 500) RETURNING order_id AS failed_order \gset
    UPDATE variants SET stock_qty = stock_qty - 5 WHERE variant_id = 1;   -- violates CHECK -> error
ROLLBACK;     -- after the error the transaction is aborted; ROLLBACK discards the order row too
SELECT count(*) AS orphan_orders_left_behind FROM orders WHERE order_id = :failed_order;
SELECT variant_id, stock_qty AS stock_unchanged FROM variants WHERE variant_id = 1;

\echo '=== Example 3: SAVEPOINT, keep the order but undo a failed optional step (gift-wrap)'
BEGIN;
    INSERT INTO orders (customer_id, status, shipping_country, total_amount)
    VALUES (2, 'pending', 'GB', 100) RETURNING order_id AS sp_order \gset
    SAVEPOINT before_giftwrap;
    INSERT INTO stock_movements (variant_id, delta, reason) VALUES (999999, -1, 'gift wrap');  -- FK error
    ROLLBACK TO SAVEPOINT before_giftwrap;
    UPDATE orders SET status = 'paid' WHERE order_id = :sp_order;
COMMIT;
SELECT order_id, status FROM orders WHERE order_id = :sp_order;

-- ---------------------------------------------------------------------
-- Reusable, atomic stored function. The single UPDATE ... WHERE stock_qty >= qty
-- both checks and decrements in one atomic statement, so two buyers can never
-- take the last item (see 02_concurrency_demo.py for the proof).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION place_order(p_customer BIGINT, p_variant BIGINT, p_qty INT, p_method TEXT)
RETURNS BIGINT LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public   -- runs with the owner's rights: callers need only EXECUTE (see Portfolio 5 RBAC)
AS $$
DECLARE
    v_order   BIGINT;
    v_price   NUMERIC(10,2);
    v_country CHAR(2);
BEGIN
    SELECT p.base_price INTO v_price
    FROM variants v JOIN products p USING (product_id) WHERE v.variant_id = p_variant;
    IF v_price IS NULL THEN RAISE EXCEPTION 'Unknown variant %', p_variant; END IF;

    UPDATE variants SET stock_qty = stock_qty - p_qty
    WHERE variant_id = p_variant AND stock_qty >= p_qty;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Insufficient stock for variant %', p_variant USING ERRCODE = 'P0001';
    END IF;

    SELECT country_code INTO v_country FROM customers WHERE customer_id = p_customer;
    INSERT INTO orders (customer_id, status, shipping_country, total_amount)
    VALUES (p_customer, 'paid', v_country, v_price * p_qty) RETURNING order_id INTO v_order;
    INSERT INTO order_items (order_id, variant_id, quantity, unit_price) VALUES (v_order, p_variant, p_qty, v_price);
    INSERT INTO payments (order_id, amount, method, payment_status) VALUES (v_order, v_price * p_qty, p_method, 'captured');
    INSERT INTO stock_movements (variant_id, delta, reason) VALUES (p_variant, -p_qty, 'sale order ' || v_order);
    RETURN v_order;
END $$;

\echo '=== Example 4: place_order() succeeds, then fails cleanly when stock is exhausted'
UPDATE variants SET stock_qty = 1 WHERE variant_id = 2;
SELECT place_order(3, 2, 1, 'card') AS first_order_id;
SELECT stock_qty FROM variants WHERE variant_id = 2;
SELECT place_order(4, 2, 1, 'card');      -- expected: ERROR Insufficient stock
SELECT stock_qty AS stock_still_zero_not_negative FROM variants WHERE variant_id = 2;
