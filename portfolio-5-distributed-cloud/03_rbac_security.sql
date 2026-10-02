-- =====================================================================
-- Portfolio 5, Security for the cloud deployment: authentication, authorisation, RBAC
-- (course slides S2_03: shared-responsibility model, the provider secures the
--  infrastructure, the customer must configure permissions correctly).
-- PostgreSQL 16 docs: Database Roles   https://www.postgresql.org/docs/16/user-manag.html
--                     Privileges       https://www.postgresql.org/docs/16/ddl-priv.html
-- Run as a superuser:  psql -d atelier_db -f 03_rbac_security.sql
-- =====================================================================
\pset pager off

-- Clean slate so the script can be re-run
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['role_analyst','role_stylist','role_checkout'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('DROP OWNED BY %I', r);
    END IF;
  END LOOP;
END $$;
DROP ROLE IF EXISTS app_analyst_anna, app_stylist_amelie, app_web;
DROP ROLE IF EXISTS role_analyst, role_stylist, role_checkout;

-- 1. Group roles = RBAC job functions; they cannot log in themselves
CREATE ROLE role_analyst  NOLOGIN;
CREATE ROLE role_stylist  NOLOGIN;
CREATE ROLE role_checkout NOLOGIN;

-- 2. Login roles = people / services, each granted exactly one job function (authentication)
CREATE ROLE app_analyst_anna   LOGIN PASSWORD 'anna_demo_pw'   IN ROLE role_analyst;
CREATE ROLE app_stylist_amelie LOGIN PASSWORD 'amelie_demo_pw' IN ROLE role_stylist;
CREATE ROLE app_web            LOGIN PASSWORD 'web_demo_pw'    IN ROLE role_checkout;

-- 3. Least privilege: start from nothing
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC;

-- Analysts: read-only, NO access to personal data columns or to payments
GRANT SELECT ON orders, order_items, products, variants, collections, mv_customer_spend TO role_analyst;
GRANT SELECT (customer_id, country_code, loyalty_tier, created_at) ON customers TO role_analyst;   -- column-level: no name/e-mail

-- Stylists: may see orders and manage fittings, nothing financial
GRANT SELECT ON orders, order_items, products, variants TO role_stylist;
GRANT SELECT, UPDATE (outcome, scheduled_at) ON fittings TO role_stylist;

-- Checkout service: can only call the audited, atomic stored function from Portfolio 3
GRANT EXECUTE ON FUNCTION place_order(BIGINT, BIGINT, INT, TEXT) TO role_checkout;
GRANT SELECT ON products, variants TO role_checkout;

\echo '=== TEST 1: analyst can aggregate orders'
SET ROLE app_analyst_anna;
SELECT shipping_country, count(*) AS orders FROM orders GROUP BY 1 ORDER BY 2 DESC LIMIT 3;

\echo '=== TEST 2: analyst tries to read client e-mail addresses (personal data) -> denied'
SELECT email FROM customers LIMIT 1;

\echo '=== TEST 3: analyst tries to read payments -> denied'
SELECT * FROM payments LIMIT 1;
RESET ROLE;

\echo '=== TEST 4: stylist may update a fitting outcome'
SET ROLE app_stylist_amelie;
UPDATE fittings SET outcome = 'completed' WHERE fitting_id = 1;

\echo '=== TEST 5: stylist tries to change an order total -> denied'
UPDATE orders SET total_amount = 1 WHERE order_id = 1;
RESET ROLE;

\echo '=== TEST 6: checkout service cannot edit stock directly, only through place_order()'
SET ROLE app_web;
UPDATE variants SET stock_qty = 9999 WHERE variant_id = 30;
SELECT place_order(5, 30, 1, 'card') AS order_created_through_function;
RESET ROLE;
