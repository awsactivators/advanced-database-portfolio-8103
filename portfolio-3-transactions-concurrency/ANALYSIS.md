# Portfolio 3: Transactions and Concurrency

Evidence is in `evidence/01_transactions.log` (SQL) and `evidence/02_concurrency_demo.log` (two real database sessions running in parallel). I run Portfolio 1 first, then `01_transactions.sql`, then `python3 02_concurrency_demo.py`.

## 1. The rule I wanted to protect

Every sale must reserve stock, write the order line, record the payment and log the stock movement, all together or not at all. A limited edition piece with one unit left makes the problem realistic, because two clients can press "buy" at the same moment.

## 2. ACID examples in SQL (`01_transactions.sql`)

| Example | What happens | Property shown |
|---|---|---|
| 1, COMMIT | The order, line, payment, stock change and log row commit together and stock goes from 3 to 2. | Atomicity, durability |
| 2, ROLLBACK | Buying 5 when 2 remain breaks `CHECK (stock_qty >= 0)`. The transaction aborts and the order row I had already inserted disappears (0 orphan orders, stock still 2). | Atomicity, consistency |
| 3, SAVEPOINT | An optional step fails on a foreign key. I roll back to the savepoint and the order still commits as paid. | Partial rollback |
| 4, `place_order()` | A stored function does the whole sale. The second buyer of the last item gets `Insufficient stock` and stock stays at 0. | Consistency and isolation through one atomic `UPDATE ... WHERE stock_qty >= qty` |

## 3. Concurrency experiments (`02_concurrency_demo.py`)

| Experiment | Technique | What I observed |
|---|---|---|
| A | Read, calculate, write at READ COMMITTED | Both buyers were accepted for one item. This is a lost update: each session wrote a value calculated from a stale read. |
| B | `SELECT ... FOR UPDATE` | The second buyer waited, then saw stock 0 and was rejected. Correct, but it blocks. |
| C | `SERIALIZABLE` with retry | One buyer got `SerializationFailure (40001)`, retried and was told it was sold out. Correct, but the application needs retry logic. |
| D1 | Two sessions lock rows 11 and 12 in opposite order | PostgreSQL aborted one with `DeadlockDetected (40P01)` and the other committed. |
| D2 | Both lock in the same ascending order | Both committed, so a consistent lock order prevents the deadlock. |

In my first run of experiment C, buyer 0 received the serialisation failure and was told the item had sold out on its second attempt, while buyer 1 completed the purchase. In my second run the roles were reversed.

### When I would use each control

* A single conditional update (`UPDATE ... WHERE stock_qty >= n`) for simple counters. I use this inside `place_order()`.
* `FOR UPDATE` when there is logic between the read and the write; keep that transaction short.
* `SERIALIZABLE` when many rows interact and locking is hard to reason about, always with a retry loop.
* A fixed lock order whenever a transaction touches several rows.

### Link to the lectures (S2_02)

The lectures cover ACID and isolation levels. My experiments show that the default level still allows lost updates when the application does its own read, calculate and write, so ACID does not remove the need to design transactions carefully. In a distributed database the same guarantees cost extra coordination (for example two-phase commit), which is the trade-off the slides describe.

## 4. Limitations

Timing based demos can vary. A barrier forces both sessions to read before either writes, so A, C and D1 reproduce reliably, but which buyer or session loses can change between runs. I ran the demo twice. In experiment C buyer 0 received the serialisation failure in the first run and buyer 1 in the second, while in D1 session 1 was aborted both times. In every run the final stock was 0 and exactly one buyer got the last item (except in A, where both were accepted).

## 5. References

* PostgreSQL Global Development Group (2024) *Transaction Isolation*. PostgreSQL 16 Documentation. https://www.postgresql.org/docs/16/transaction-iso.html
* PostgreSQL Global Development Group (2024) *Explicit Locking*. https://www.postgresql.org/docs/16/explicit-locking.html
* PostgreSQL Global Development Group (2024) *SAVEPOINT*. https://www.postgresql.org/docs/16/sql-savepoint.html
* Obunadike, G.N. (2026) *CAP Theorem, ACID, and BASE Models* [Lecture slides, MIT 8103 S2_02]. Miva Open University.
* Silberschatz, A., Korth, H.F. and Sudarshan, S. (2020) *Database System Concepts*. 7th edn. McGraw-Hill Education.
