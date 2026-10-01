# Portfolio 2: Query Processing and Optimisation

The numbers below come from the logs in `evidence/`, which I produced on PostgreSQL 16 on my Mac with parallel query switched off so the plans are easy to compare. Timings will differ on another computer; the plan shapes and the relative gains are what matter.

## 1. The five queries (`01_queries_explain.sql`)

| # | Business question | Features |
|---|---|---|
| Q1 | Order history of one client, found by e-mail | join, `ORDER BY` |
| Q2 | Monthly revenue by shipping country for the last 12 months | range filter, `GROUP BY` |
| Q3 | Ten best-selling pieces in collection "AW 2025" | four table join, aggregate |
| Q4 | Top 3 spenders per country | CTE and window function |
| Q5 | Pending orders older than 30 days | selective filter |

## 2. What the plans showed before indexing

* Q1 found the client quickly through the unique e-mail index, then scanned all 120,000 orders because `orders.customer_id` had no index. PostgreSQL does not index foreign key columns by itself.
* Q2, Q4 and Q5 used sequential scans on `orders`.
* Q3 scanned all 240,000 rows of `order_items` because `variant_id` had no index.

My first run of the five queries was much slower than later runs (Q1 took about 160 ms) because the cache was cold. I ran the "before" file a second time and used that run, so the before and after comparison is fair.

## 3. Indexes I created (`02_indexes.sql`)

| Index | Why |
|---|---|
| `orders (customer_id, order_date DESC)` | Finds one client's orders already sorted. |
| `orders (order_date) INCLUDE (shipping_country, total_amount)` with a `WHERE` on settled statuses | A partial, covering index, so Q2 can be answered from the index alone. The plan showed `Heap Fetches: 0`, which confirms it never had to visit the table. |
| `products (collection_id)` and `order_items (variant_id)` | Join path for Q3. |
| `orders (order_date) WHERE status = 'pending'` | Small partial index, since Q5 only touches pending rows. |

## 4. Results

| Query | Before (ms) | After (ms) | Plan change | My comment |
|---|---:|---:|---|---|
| Q1 | 30.892 | 0.724 | Seq Scan and Hash Join became a Bitmap Index Scan | About 43 times faster. About 2,128 buffers before and about 15 after. |
| Q2 | 25.183 | 33.443 | Seq Scan became an Index Only Scan with 0 heap fetches | No gain. Reading about 34,000 index entries took about 17 ms, and the aggregation still had to process every one of those rows. |
| Q3 | 30.561 | 29.295 | Seq Scan on `order_items` became 200 Index Scans on `idx_order_items_variant` | The plan reads about 20,000 rows instead of 240,000, but 200 small lookups cost about the same as one pass over a table that fits in memory, so the time barely changed. |
| Q4 | 46.674 | 57.190 | No change, still a Seq Scan | Expected. The difference is within normal run to run variation. |
| Q5 | 6.137 | 0.199 | Seq Scan became an Index Scan on the partial index | About 31 times faster. The partial index is tiny. |

Q1 and Q5 improved clearly because each returns a small part of the table. Q2 and Q4 have to read a large share of `orders` whatever indexes exist. Q3 reads far fewer rows with the index, but on a table that fits in memory the saving was cancelled out by the cost of many small lookups.

## 5. Why Q4 did not improve, and the materialised view

Q4 has to read every settled order to total each client's spend, so no index can save it from that work and the planner was right to keep the sequential scan. I changed the approach instead of adding another index. `03_materialised_view.sql` stores one row per country and client in `mv_customer_spend`.

| Measure | Result |
|---|---|
| Q4 against the view | 3.72 ms compared with 46.67 ms live, about 12.5 times faster |
| Refresh cost | `REFRESH MATERIALIZED VIEW CONCURRENTLY` took about 147 ms and does not block readers, because the view has a unique index |
| Trade-off I demonstrated | After I added 1,000 to one order the live total was 34,834.53 while the view still showed 33,834.53, until I refreshed it. |

My conclusion is that indexes suit selective lookups and joins, while a materialised view suits heavy repeated aggregates that can tolerate slightly old data. I would never use a view for something that must be exact at read time, such as stock at checkout (see Portfolio 3).

## 6. Limitations

* The data is random and evenly spread, while real data is skewed and could change the plans.
* The whole dataset fits in memory. On disk-bound cloud storage the gap between indexed and unindexed queries would probably be larger, and Q2 and Q3 might then benefit from their indexes.
* Each time comes from a single run. Q4 changed by about 10 ms with no relevant change to the query, so differences of that size are noise.
* An index changing the plan does not guarantee a faster query. On a small dataset held in memory a sequential scan is cheap, so some of my indexes changed the plan without changing the time.
* I did not measure how much the indexes slow down writes.

## 7. References

* PostgreSQL Global Development Group (2024) *Using EXPLAIN*. PostgreSQL 16 Documentation. https://www.postgresql.org/docs/16/using-explain.html
* PostgreSQL Global Development Group (2024) *Indexes*. https://www.postgresql.org/docs/16/indexes.html
* PostgreSQL Global Development Group (2024) *CREATE MATERIALIZED VIEW*. https://www.postgresql.org/docs/16/sql-creatematerializedview.html
* Obunadike, G.N. (2026) *Caching Strategies and Materialised Views* [Lecture slides, MIT 8103 S2_04]. Miva Open University.
* Silberschatz, A., Korth, H.F. and Sudarshan, S. (2020) *Database System Concepts*. 7th edn. McGraw-Hill Education.