# Portfolio 4: NoSQL and Advanced Data Models

I kept the same case study (Atelier Verane). I implemented two NoSQL models and designed two more, choosing each one for a specific access pattern.

## 1. Which model for which job

| Access pattern | Best fit | Done? | Why the relational model alone is not ideal |
|---|---|---|---|
| Product catalogue with attributes that differ by category | Document (MongoDB) | Implemented | Gowns, coats and knitwear need different attributes. In SQL that means many NULL columns or an attribute table, and each new attribute is a schema change. |
| Cart, session, price cache, trending list | Key-value (Redis) | Implemented | Very high read and write rate, short-lived data, no joins. |
| "Clients who bought this also bought" | Graph (for example Neo4j) | Design only | Multi-hop traversals need repeated self-joins in SQL. |
| Web event logs | Column-family (for example Cassandra) | Discussion only | Append-heavy data that is aggregated by time window. |

## 2. Document model (MongoDB)

* One document per product, with the `variants` array embedded (always read together with the product and capped at 10 entries) and a small `collection` summary embedded too. Category-specific fields live in an `attributes` sub-document.
* I did not embed orders inside products, because orders grow without limit and are written at a different rate. In MongoDB they would reference the product by `_id` (the SKU).
* `02_mongodb_catalogue.js` adds a `$jsonSchema` validator (core fields mandatory, everything else free), compound and nested indexes, an `$elemMatch` query, a `$unwind` and `$group` aggregation, a new attribute added without any migration, and a stock decrement with a majority write concern.
* `03_test_document_logic.py` checks the logic without needing a server. It loads the exported documents into mongomock and confirms that 240 documents and 2,400 variants were exported, that `neckline` exists only on gowns, that a new attribute can be added to one document only, and that stock totals per collection match PostgreSQL (`evidence/03_document_logic_test.log`). mongomock does not enforce `$jsonSchema`, so I also ran the `.js` file on a real MongoDB instance for the validator and aggregation screenshots.
* I encountered `MongoServerError: user is not allowed to do action [collMod] on [atelier_nosql.products]` error because my Atlas user needed the `dbAdmin` role on the database before `collMod` was allowed and not Read and write role.

## 3. Key-value model (Redis), see `evidence/04_redis_demo.log`

| Key pattern | Type | Notes |
|---|---|---|
| `cart:<customer>` | Hash with a 24 hour TTL | `HINCRBY` is atomic, so there is no lost update like experiment A in Portfolio 3. |
| `session:<token>` | String with a TTL | I used a 1 second TTL to show it expiring on its own. |
| `price:<sku>` | String with a 5 minute TTL | Cache-aside: read Redis, and on a miss read PostgreSQL and store the result. |
| `trending:day` | Sorted set | `ZINCRBY` and `ZREVRANGE` give a live top list without a `GROUP BY`. |

In my test the median price lookup was 0.076 ms from PostgreSQL and 0.036 ms from a Redis hit, so Redis was about twice as fast. In absolute terms both are tiny, because they run on my machine and PostgreSQL already has the data in memory; the real benefit is taking read load off the primary database. I also showed the invalidation problem: after I changed a price from 2200.25 to 2210.25, Redis kept returning the old value until I deleted the key, which is the stale data risk in the caching slides (S2_04).
## 4. Graph model (design only)

Nodes are `(:Client)`, `(:Product)` and `(:Collection)`, with `(:Client)-[:PURCHASED]->(:Product)` and `(:Product)-[:IN_COLLECTION]->(:Collection)`. A recommendation query in Cypher would be:

```cypher
MATCH (me:Client {id: $id})-[:PURCHASED]->(p:Product)<-[:PURCHASED]-(peer:Client)-[:PURCHASED]->(rec:Product)
WHERE NOT (me)-[:PURCHASED]->(rec)
RETURN rec.name, count(DISTINCT peer) AS peers ORDER BY peers DESC LIMIT 5
```

The SQL version needs three self-joins on `order_items`, while a graph database handles extra depth cheaply. A graph is a poor fit for bulk aggregates such as monthly revenue, so PostgreSQL stays the system of record.

## 5. Column-family (discussion)

Web events like `(session_id, ts, page, country)` partitioned by day in Cassandra give cheap writes and time-window scans, and favour availability over immediate consistency. That is fine for analytics but not for payments.

## 6. Overall suitability

PostgreSQL for payments, stock and orders (ACID); MongoDB for the catalogue; Redis for cart, session and cache; a graph for recommendations. This matches the slides' advice on hybrid designs, with ACID for payments and BASE for things like reviews (S2_02).

## 7. References

* MongoDB Inc. (2024) *MongoDB Manual: Schema Validation, Aggregation Pipeline, Data Modeling*. https://www.mongodb.com/docs/manual/
* Redis Ltd. (2024) *Redis commands: HSET, HINCRBY, EXPIRE, ZINCRBY*. https://redis.io/docs/latest/commands/
* Neo4j Inc. (2024) *Cypher Manual*. https://neo4j.com/docs/cypher-manual/current/
* Obunadike, G.N. (2026) *Features of Advanced Database Systems* [S2_01], *CAP Theorem, ACID, and BASE Models* [S2_02] and *Caching Strategies and Materialised Views* [S2_04]. Lecture slides, MIT 8103. Miva Open University.
