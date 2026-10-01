-- =====================================================================
-- Portfolio 1, Synthetic seed data (setseed makes random() repeatable)
-- Volumes: 12 collections, 240 products, 2,400 variants, 20,000 customers,
--          120,000 orders, ~240,000 order items (enough for meaningful plans)
-- All data is artificial and generated here, no real personal data.
-- =====================================================================
SELECT setseed(0.42);

INSERT INTO collections (collection_name, season, collection_year)
SELECT s.season || ' ' || y.yr, s.season, y.yr
FROM (VALUES ('SS'),('AW'),('RESORT'),('COUTURE')) AS s(season)
CROSS JOIN (VALUES (2024),(2025),(2026)) AS y(yr);

INSERT INTO products (collection_id, sku, product_name, category, base_price, made_to_order, lead_time_days)
SELECT 1 + (g % 12),
       'AV-' || lpad(g::text, 5, '0'),
       (ARRAY['Bias','Silk','Wool','Velvet','Cashmere','Organza'])[1 + g % 6] || ' ' ||
       (ARRAY['Gown','Coat','Dress','Blazer','Sweater','Scarf'])[1 + g % 6] || ' No.' || g,
       (ARRAY['gown','coat','dress','tailoring','knitwear','accessory'])[1 + g % 6],
       round((120 + random() * 2800)::numeric, 2),
       (random() < 0.30),
       0
FROM generate_series(1, 240) AS g;

-- made-to-order pieces need a production lead time (21-60 days)
UPDATE products SET lead_time_days = 21 + (product_id % 40) WHERE made_to_order;

INSERT INTO variants (product_id, size_label, colour, stock_qty)
SELECT p.product_id, s.sz, c.col, (random() * 40)::int
FROM products p
CROSS JOIN (VALUES ('XS'),('S'),('M'),('L'),('XL')) AS s(sz)
CROSS JOIN (VALUES ('Ivory'),('Noir')) AS c(col);

INSERT INTO customers (full_name, email, country_code, loyalty_tier, created_at)
SELECT 'Client ' || g,
       'client' || g || '@example.com',
       (ARRAY['FR','GB','US','CA','NG','AE','DE','IT','JP','ZA','SG','BR'])[1 + (random()*11)::int],
       (ARRAY['standard','standard','standard','silver','gold','private'])[1 + (random()*5)::int],
       timestamptz '2023-06-01' + random() * interval '1000 days'
FROM generate_series(1, 20000) AS g;

INSERT INTO orders (customer_id, order_date, status, shipping_country)
SELECT c.customer_id,
       timestamptz '2024-01-01' + random() * (timestamptz '2026-09-30' - timestamptz '2024-01-01'),
       (ARRAY['paid','paid','shipped','delivered','delivered','in_production','pending','cancelled'])[1 + (random()*7)::int],
       c.country_code
FROM (SELECT 1 + (random()*19999)::int AS cid FROM generate_series(1, 120000)) r
JOIN customers c ON c.customer_id = r.cid;

-- each order gets 1-3 distinct variants (offset 13*k guarantees distinct variant ids)
INSERT INTO order_items (order_id, variant_id, quantity, unit_price)
SELECT o.order_id, v.variant_id, 1 + (random()*2)::int, p.base_price
FROM orders o
CROSS JOIN generate_series(0, 2) AS k
JOIN variants v ON v.variant_id = 1 + ((o.order_id * 7 + k * 13) % 2400)
JOIN products p ON p.product_id = v.product_id
WHERE k < 1 + (o.order_id % 3);

UPDATE orders o SET total_amount = t.tot
FROM (SELECT order_id, sum(quantity * unit_price) AS tot FROM order_items GROUP BY order_id) t
WHERE t.order_id = o.order_id;

INSERT INTO payments (order_id, amount, method, payment_status, paid_at)
SELECT order_id, total_amount,
       (ARRAY['card','card','bank_transfer','wallet'])[1 + (random()*3)::int],
       'captured', order_date + interval '5 minutes'
FROM orders
WHERE status IN ('paid','in_production','shipped','delivered') AND total_amount > 0;

INSERT INTO fittings (order_item_id, scheduled_at, stylist_name, outcome)
SELECT oi.order_item_id, o.order_date + interval '14 days',
       (ARRAY['Amelie','Chloe','Ingrid','Tomas'])[1 + (random()*3)::int],
       (ARRAY['completed','completed','alterations_required','scheduled'])[1 + (random()*3)::int]
FROM order_items oi
JOIN orders o   ON o.order_id = oi.order_id
JOIN variants v ON v.variant_id = oi.variant_id
JOIN products p ON p.product_id = v.product_id
WHERE p.made_to_order AND o.status <> 'cancelled';

ANALYZE;
