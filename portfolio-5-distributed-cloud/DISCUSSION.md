# Portfolio 5: Distributed and Cloud Database Exercise

Atelier Verane sells in 12 countries, so one server in one region would mean slow checkouts overseas and a single point of failure. For this portfolio I built a working replication and partitioning lab and wrote a cloud deployment analysis.

## 1. Replication (01_replication_demo_mac.sh, evidence in 01_replication_demo.log)

I set up a PostgreSQL 16 primary (port 5432) and a hot standby replica (port 5433) with `pg_basebackup -R` and asynchronous streaming replication. A dedicated `replicator` role has only the `REPLICATION` privilege.

| Step | What I saw |
|---|---|
| Status on the primary | `pg_stat_replication` showed `streaming` and `async`. |
| Write on primary, read on replica | The new stock value appeared on the replica. |
| Write on the replica | `ERROR: cannot execute UPDATE in a read-only transaction`, and `pg_is_in_recovery()` returned true. |
| Replication lag | 20,000 rows committed on the primary in about 66 ms, and the replica showed all of them about 20 ms after the commit returned. That timing includes starting the client, so it is an upper bound on one machine. My first check already found all 20,000 rows, so I did not catch the replica behind this time. The window still exists in principle: the primary does not wait for the replica, which is eventual consistency, and between regions it would be much longer. |
| Fail-over | `pg_ctl promote` turned the replica into a writable primary and my test write was accepted. |

Asynchronous replication favours availability and fast commits. If the primary were lost after a commit but before the replica caught up, the last transactions could be lost. Synchronous replication would fix that at the price of slower commits and refusing writes when the standby is unreachable, which is the CP choice in the CAP discussion (S2_02). For payments I would choose synchronous; for catalogue browsing, asynchronous read replicas are fine.

## 2. Sharding and partitioning (`02_partitioning_sharding.sql`, evidence in `02_partitioning_sharding.log`)

Partitioning is the single server version of sharding. In Spanner, CockroachDB or Citus each partition would sit on its own node.

| Strategy | Result | Use |
|---|---|---|
| Range by `order_date` (2024, 2025, 2026) | 43,691, 43,611 and 32,701 rows. A query for March 2025 scanned only `orders_2025` (partition pruning), while a query without a date scanned all three. | Archiving old years and time-window reports. |
| Hash by `customer_id` into 4 shards | 24.8%, 25.3%, 25.3% and 24.6%, almost even. A query with `customer_id = 4242` went to one shard, and a query without the shard key hit all four (scatter-gather). | Spreading write load; the shard key decides which queries are cheap. |

I chose `customer_id` as the shard key because "show my orders" stays on one shard and the load is even. A country-wide revenue report has to fan out, so in a real system I would run that from a replicated analytics store or a materialised view (Portfolio 2). Sharding by country would be skewed because some markets are much bigger than others.

## 3. Security (`03_rbac_security.sql`, evidence in `03_rbac_security.log`)

This follows the shared responsibility model from the lectures (S2_03): the provider secures the infrastructure and I must configure identities and permissions properly.

| Test | Outcome |
|---|---|
| Analyst aggregates orders | Allowed |
| Analyst reads client e-mail addresses | `permission denied for table customers`, because a column level `GRANT` exposes only non-identifying columns |
| Analyst reads payments | `permission denied` |
| Stylist updates a fitting outcome | Allowed (column level `UPDATE`) |
| Stylist edits an order total | `permission denied` |
| Checkout service edits stock directly | `permission denied`; only `place_order()` works |

The idea is least privilege through roles. Group roles represent job functions and the login roles inherit them. Rules such as GDPR and Nigeria's NDPA are a good reason to keep personal data away from analysts.

## 4. How this maps to managed cloud services

| Need | My lab | Managed equivalent (examples) |
|---|---|---|
| Read replicas and fail-over | `pg_basebackup`, `pg_ctl promote` | Amazon RDS Multi-AZ and read replicas, Google Cloud SQL replicas |
| Global consistency | Synchronous standby | Google Spanner (TrueTime), CockroachDB |
| Catalogue documents | Local MongoDB | MongoDB Atlas, where an M0 free cluster is a three node replica set |
| Cache | Local Redis | AWS ElastiCache, Google Memorystore |
| Identity | PostgreSQL roles | IAM based database authentication and MFA |

## 5. The architecture I would recommend

1. A PostgreSQL primary with a synchronous standby in a second zone for orders, payments and stock (CP and ACID).
2. Asynchronous read replicas near Europe, North America and Africa for catalogue and order history reads.
3. A MongoDB replica set for the catalogue and Redis for cart, session and cache.
4. Orders partitioned by year, and hash sharded by customer only when one primary can no longer keep up.
5. Nightly materialised views or a warehouse for dashboards.

## 6. Cloud deployment evidence

I created a free MongoDB Atlas M0 cluster, loaded portfolio-4-nosql/products.json with mongoimport and ran 02_mongodb_catalogue.js on it. db.hello() reported a replica set with 3 members, one primary and two secondaries, which Atlas manages for me (log: evidence/04_atlas_replica_set.log). My first check, a plain hello command, was answered by the primary (secondary: false), so I used explain to see where a read actually ran. A query with the secondary read preference ran on a different node from the primary and returned all 240 products, so the data had been replicated. My database user needed the dbAdmin role on atelier_nosql before the script could add the schema validator, and access was limited to my own IP address. I checked the current M0 limits on the MongoDB pricing page before starting.

## 7. Limitations

Both PostgreSQL servers ran on one machine, so network latency and real partitions were not tested. Fail-over was manual, whereas production would use an orchestrator such as Patroni or the cloud provider's automation. The partitions share one disk.

## 8. References

* PostgreSQL Global Development Group (2024) *High Availability, Load Balancing, and Replication*. https://www.postgresql.org/docs/16/high-availability.html
* PostgreSQL Global Development Group (2024) *Table Partitioning*. https://www.postgresql.org/docs/16/ddl-partitioning.html
* PostgreSQL Global Development Group (2024) *Database Roles* and *Privileges*. https://www.postgresql.org/docs/16/user-manag.html
* MongoDB Inc. (2024) *Replication*. MongoDB Manual. https://www.mongodb.com/docs/manual/replication/
* Brewer, E. (2012) 'CAP twelve years later: how the "rules" have changed', *Computer*, 45(2), pp. 23 to 29.
* Obunadike, G.N. (2026) Lecture slides MIT 8103 S2_01, S2_02 and S2_03. Miva Open University.
* Özsu, M.T. and Valduriez, P. (2020) *Principles of Distributed Database Systems*. 4th edn. Springer.
