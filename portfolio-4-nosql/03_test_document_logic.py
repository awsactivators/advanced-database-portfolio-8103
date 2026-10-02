#!/usr/bin/env python3
"""
Portfolio 4, Step 3: automated check of the document queries WITHOUT needing a MongoDB server.

mongomock is an in-memory stand-in that implements the pymongo API. It lets me verify that the
find / update / aggregation logic used in 02_mongodb_catalogue.js returns the expected results.
Limitation: mongomock does not enforce $jsonSchema validators or real
replication, so those parts of the script must be run against a real MongoDB / Atlas instance.

    pip install mongomock
    python3 03_test_document_logic.py
"""
import json
import os
import mongomock

here = os.path.dirname(os.path.abspath(__file__))
docs = json.load(open(os.path.join(here, "products.json"), encoding="utf-8"))

client = mongomock.MongoClient()
col = client.atelier_nosql.products
col.insert_many(docs)
print(f"Loaded {col.count_documents({})} documents")

# 1. attribute that exists only on some categories
gowns = list(col.find({"category": "gown", "attributes.neckline": {"$exists": True}}, {"name": 1, "attributes.neckline": 1}))
only_gowns_have_neckline = col.count_documents({"attributes.neckline": {"$exists": True}}) == col.count_documents({"category": "gown"})
print(f"gowns with neckline: {len(gowns)}; neckline exists ONLY on gowns -> {only_gowns_have_neckline}")
assert only_gowns_have_neckline

# 2. embedded-array query
hits = col.count_documents({"variants": {"$elemMatch": {"size": "M", "colour": "Noir", "stock": {"$gt": 30}}}})
print(f"products with an M/Noir variant holding > 30 units: {hits}")

# 3. schema evolution without migration
col.update_one({"_id": "AV-00003"}, {"$set": {"attributes.sustainabilityCertified": True}})
assert col.find_one({"_id": "AV-00003"})["attributes"]["sustainabilityCertified"] is True
assert col.find_one({"_id": "AV-00004"})["attributes"].get("sustainabilityCertified") is None
print("new attribute added to ONE document only, no ALTER TABLE, other documents untouched")

# 4. aggregation
agg = list(col.aggregate([
    {"$unwind": "$variants"},
    {"$group": {"_id": "$collection.name", "totalStock": {"$sum": "$variants.stock"}, "avgPrice": {"$avg": "$basePrice"}}},
    {"$sort": {"totalStock": -1}},
]))
print("top 3 collections by stock:")
for r in agg[:3]:
    print(f"   {r['_id']:<14} stock={r['totalStock']:>5}  avgPrice={r['avgPrice']:.2f}")
assert len(agg) == 12

# 5. cross-check against PostgreSQL (same totals => the export lost nothing)
try:
    import psycopg2
    dsn = os.environ.get("PGDSN", "dbname=atelier_db user=postgres password=postgres host=localhost")
    with psycopg2.connect(dsn) as c, c.cursor() as cur:
        cur.execute("""SELECT c.collection_name, sum(v.stock_qty) FROM variants v
                       JOIN products p USING (product_id) JOIN collections c USING (collection_id)
                       GROUP BY 1""")
        pg = {k: int(v) for k, v in cur.fetchall()}
    mg = {r["_id"]: r["totalStock"] for r in agg}
    print("Stock totals per collection identical in PostgreSQL and in the documents:", pg == mg)
    assert pg == mg
except ImportError:
    print("psycopg2 not installed, skipped cross-check")
print("ALL CHECKS PASSED")
