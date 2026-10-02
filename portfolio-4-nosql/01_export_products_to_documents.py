#!/usr/bin/env python3
"""
Portfolio 4, Step 1: build the DOCUMENT model from the relational data.

Why documents? In the relational design every product shares the same columns, but a
couture gown (neckline, train length, lining) and a knitwear piece (yarn, gauge) need
different attributes. Modelling that in SQL means many NULL columns or an
entity-attribute-value table. A document keeps the variable part inside one record and
embeds the size/colour variants that are always read together with the product.

Usage:
    export PGDSN="dbname=atelier_db user=postgres password=YOURPASSWORD host=localhost"
    python3 01_export_products_to_documents.py          # writes products.json
"""
import json
import os
import psycopg2

DSN = os.environ.get("PGDSN", "dbname=atelier_db user=postgres password=postgres host=localhost")

# Category-specific attributes (the 'schema-less' part). Values are illustrative.
ATTRS = {
    "gown":      lambda pid: {"neckline": ["sweetheart", "bateau", "halter"][pid % 3],
                              "trainLengthCm": 20 + pid % 60, "lining": "silk charmeuse"},
    "coat":      lambda pid: {"fabricComposition": {"wool": 80, "cashmere": 20},
                              "insulation": ["none", "light", "thermal"][pid % 3]},
    "dress":     lambda pid: {"sleeve": ["sleeveless", "cap", "long"][pid % 3], "lengthCm": 90 + pid % 40},
    "tailoring": lambda pid: {"fit": ["slim", "regular"][pid % 2], "buttons": 2 + pid % 3},
    "knitwear":  lambda pid: {"yarn": "merino", "gauge": 7 + pid % 6},
    "accessory": lambda pid: {"dimensionsCm": {"w": 60 + pid % 30, "h": 60 + pid % 30},
                              "hardware": "gold-tone"},
}

SQL = """
SELECT p.product_id, p.sku, p.product_name, p.category, p.base_price, p.made_to_order,
       p.lead_time_days, c.collection_name, c.season, c.collection_year,
       json_agg(json_build_object('size', v.size_label, 'colour', v.colour, 'stock', v.stock_qty)
                ORDER BY v.variant_id) AS variants
FROM products p
JOIN collections c ON c.collection_id = p.collection_id
JOIN variants v    ON v.product_id = p.product_id
GROUP BY p.product_id, c.collection_id
ORDER BY p.product_id
"""


def main():
    with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute(SQL)
        docs = []
        for (pid, sku, name, cat, price, mto, lead, cname, season, year, variants) in cur.fetchall():
            docs.append({
                "_id": sku,
                "name": name,
                "category": cat,
                "basePrice": float(price),
                "madeToOrder": mto,
                "leadTimeDays": lead,
                "collection": {"name": cname, "season": season, "year": year},
                "attributes": ATTRS[cat](pid),
                "variants": variants,
            })
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "products.json")
    with open(out, "w", encoding="utf-8") as f:
        json.dump(docs, f, indent=1)
    print(f"Wrote {len(docs)} product documents to {out}")
    print("Example document:\n" + json.dumps(docs[0], indent=2))


if __name__ == "__main__":
    main()
