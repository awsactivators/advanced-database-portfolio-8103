# Advanced Database Systems Portfolio, MIT 8103 (2026/2027)

**Name:** Amaka Genevieve Jane Awa  
**Student ID:** 301915927  
**Programme:** Master of Information Technology, Miva Open University  
**Case study:** Atelier Verane, a simulated made-to-order luxury fashion house with an online shop, fittings for bespoke pieces and clients in 12 countries. All the data is synthetic.

## What is in this repository

| Folder | Activity | Main files | Evidence |
|---|---|---|---|
| `portfolio-1-database-design/` | Design and modelling | `DESIGN.md`, `01_schema.sql`, `02_seed_data.sql`, `er_diagram.png` | row counts, screenshots |
| `portfolio-2-query-optimisation/` | Query processing and optimisation | `ANALYSIS.md`, three SQL scripts | `EXPLAIN ANALYZE` logs before and after, screenshots |
| `portfolio-3-transactions-concurrency/` | Transactions and concurrency | `ANALYSIS.md`, `01_transactions.sql`, `02_concurrency_demo.py` | commit, rollback, lost update, locking and deadlock logs, screenshots |
| `portfolio-4-nosql/` | NoSQL and advanced models | `MODEL.md`, MongoDB script, Redis script | document test, Redis and MongoDB logs, screenshots |
| `portfolio-5-distributed-cloud/` | Distributed and cloud | `DISCUSSION.md`, replication, partitioning and security scripts | logs for each, Atlas screenshots |

Each portfolio folder keeps its logs in `evidence/` and its screenshots in `evidence/screenshots/`.

## Environment

I did all the work on a Mac, using Homebrew.

* PostgreSQL 16 and Redis, both installed with Homebrew and started with `brew services`
* Python 3.12 in a virtual environment (`psycopg2-binary`, `redis`, `mongomock`)
* Graphviz for the ER diagram
* `mongosh` and `mongodb-database-tools`, with a free MongoDB Atlas M0 cluster for the document model

## How to reproduce my work

Run the steps in this order. Portfolios 2, 3 and 5 depend on the data from Portfolio 1, and Portfolio 5 also uses the view from Portfolio 2 and the function from Portfolio 3.

```bash
# Setup, once per terminal
source ~/dbenv/bin/activate
export PGDSN="dbname=atelier_db host=localhost"

# Portfolio 1
createdb atelier_db
psql -d atelier_db -f portfolio-1-database-design/01_schema.sql
psql -d atelier_db -f portfolio-1-database-design/02_seed_data.sql
python portfolio-1-database-design/03_generate_er_diagram.py

# Portfolio 2 (the order matters: plans, indexes, plans again, then the view)
psql -d atelier_db -f portfolio-2-query-optimisation/01_queries_explain.sql > portfolio-2-query-optimisation/evidence/01_plans_BEFORE_indexes.log 2>&1
psql -d atelier_db -f portfolio-2-query-optimisation/02_indexes.sql
psql -d atelier_db -f portfolio-2-query-optimisation/01_queries_explain.sql > portfolio-2-query-optimisation/evidence/02_plans_AFTER_indexes.log 2>&1
psql -d atelier_db -f portfolio-2-query-optimisation/03_materialised_view.sql > portfolio-2-query-optimisation/evidence/03_materialised_view.log 2>&1

# Portfolio 3
psql -d atelier_db -f portfolio-3-transactions-concurrency/01_transactions.sql
python portfolio-3-transactions-concurrency/02_concurrency_demo.py

# Portfolio 4 (Redis must be running: brew services start redis)
python portfolio-4-nosql/01_export_products_to_documents.py
python portfolio-4-nosql/03_test_document_logic.py
python portfolio-4-nosql/04_redis_keyvalue_demo.py
export MONGODB_URI="mongodb+srv://USER:PASSWORD@CLUSTER.mongodb.net/"    # my own Atlas details, never committed
mongoimport --uri "$MONGODB_URI" --db atelier_nosql --collection products --jsonArray --file portfolio-4-nosql/products.json --drop
mongosh "$MONGODB_URI" --file portfolio-4-nosql/02_mongodb_catalogue.js

# Portfolio 5
psql -d atelier_db -f portfolio-5-distributed-cloud/02_partitioning_sharding.sql
psql -d atelier_db -f portfolio-5-distributed-cloud/03_rbac_security.sql
bash portfolio-5-distributed-cloud/01_replication_demo_mac.sh
```

Timings will differ between machines, but the plan shapes and relative improvements should match. The passwords inside the SQL scripts are throw-away demo values for local roles. My Atlas connection string and password are never stored in the repository.

My Atlas user needed the `dbAdmin` role on `atelier_nosql` before the MongoDB script could add the schema validator.

## Headline results

* Indexing cut the client order history query from 30.9 ms to 0.72 ms, and the pending orders query from 6.1 ms to 0.20 ms. Two other queries did not get faster even though their plans changed, which I explain in `portfolio-2-query-optimisation/ANALYSIS.md`.
* One aggregate (top spenders) could not be helped by an index, so I used a materialised view and went from 46.7 ms to 3.7 ms, at the cost of slightly old data until a refresh.
* A naive stock update oversold the last item. `FOR UPDATE` and `SERIALIZABLE` with retry both fixed it, and I produced and then avoided a deadlock with a consistent lock order.
* I modelled the catalogue as documents, so attributes that differ by category need no migration, and used Redis for carts, sessions and caching with TTLs. A cached price was served about twice as fast as the same lookup from PostgreSQL.
* I ran streaming replication with fail-over, range and hash partitioning, and role based security with denied access tests. The Atlas cluster reported a replica set with three members.

## Limitations

The data is synthetic and evenly random, the PostgreSQL work ran on one machine, mongomock does not enforce `$jsonSchema` (so I used a real MongoDB cluster for that part), and the graph and column-family models are designs only.

## AI use

See `AI_USE_DECLARATION.md`.

## References

Each write-up ends with its references, and `REFERENCES.md` has the full list.