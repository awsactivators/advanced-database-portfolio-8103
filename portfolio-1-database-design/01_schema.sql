-- =====================================================================
-- Portfolio 1, Database design: physical schema (PostgreSQL 16)
-- Case study: Atelier Verane (simulated made-to-order luxury fashion house)
-- Run:  createdb atelier_db && psql -d atelier_db -f 01_schema.sql
-- =====================================================================
DROP TABLE IF EXISTS stock_movements, fittings, payments, order_items,
                     orders, variants, products, collections, customers CASCADE;

CREATE TABLE customers (
    customer_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name     VARCHAR(120) NOT NULL,
    email         VARCHAR(255) NOT NULL UNIQUE,
    country_code  CHAR(2)      NOT NULL,
    loyalty_tier  TEXT         NOT NULL DEFAULT 'standard'
                  CHECK (loyalty_tier IN ('standard','silver','gold','private')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE collections (
    collection_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    collection_name VARCHAR(80) NOT NULL UNIQUE,
    season          TEXT NOT NULL CHECK (season IN ('SS','AW','RESORT','COUTURE')),
    collection_year SMALLINT NOT NULL CHECK (collection_year BETWEEN 2000 AND 2100)
);

CREATE TABLE products (
    product_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    collection_id   INT NOT NULL REFERENCES collections(collection_id),
    sku             VARCHAR(30) NOT NULL UNIQUE,
    product_name    VARCHAR(150) NOT NULL,
    category        TEXT NOT NULL
                    CHECK (category IN ('gown','coat','dress','tailoring','knitwear','accessory')),
    base_price      NUMERIC(10,2) NOT NULL CHECK (base_price > 0),
    made_to_order   BOOLEAN NOT NULL DEFAULT false,
    lead_time_days  SMALLINT NOT NULL DEFAULT 0 CHECK (lead_time_days >= 0),
    active          BOOLEAN NOT NULL DEFAULT true
);

CREATE TABLE variants (
    variant_id  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id  BIGINT NOT NULL REFERENCES products(product_id) ON DELETE CASCADE,
    size_label  VARCHAR(10) NOT NULL,
    colour      VARCHAR(30) NOT NULL,
    stock_qty   INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),   -- consistency rule: never negative
    UNIQUE (product_id, size_label, colour)
);

CREATE TABLE orders (
    order_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id      BIGINT NOT NULL REFERENCES customers(customer_id),
    order_date       TIMESTAMPTZ NOT NULL DEFAULT now(),
    status           TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending','paid','in_production','shipped','delivered','cancelled')),
    shipping_country CHAR(2) NOT NULL,
    total_amount     NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0)
);

CREATE TABLE order_items (
    order_item_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      BIGINT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    variant_id    BIGINT NOT NULL REFERENCES variants(variant_id),
    quantity      INT NOT NULL CHECK (quantity > 0),
    unit_price    NUMERIC(10,2) NOT NULL CHECK (unit_price >= 0),  -- price frozen at purchase time
    UNIQUE (order_id, variant_id)
);

CREATE TABLE payments (
    payment_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id       BIGINT NOT NULL REFERENCES orders(order_id),
    amount         NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    method         TEXT NOT NULL CHECK (method IN ('card','bank_transfer','wallet')),
    payment_status TEXT NOT NULL CHECK (payment_status IN ('authorised','captured','failed','refunded')),
    paid_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE fittings (
    fitting_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_item_id BIGINT NOT NULL REFERENCES order_items(order_item_id) ON DELETE CASCADE,
    scheduled_at  TIMESTAMPTZ NOT NULL,
    stylist_name  VARCHAR(80) NOT NULL,
    outcome       TEXT NOT NULL DEFAULT 'scheduled'
                  CHECK (outcome IN ('scheduled','completed','alterations_required','cancelled'))
);

-- Audit trail used in Portfolio 3 (every stock change is logged)
CREATE TABLE stock_movements (
    movement_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    variant_id  BIGINT NOT NULL REFERENCES variants(variant_id),
    delta       INT NOT NULL,
    reason      VARCHAR(60) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
