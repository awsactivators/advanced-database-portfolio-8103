#!/usr/bin/env python3
"""
Portfolio 1, Generates the ER diagram directly from the LIVE database catalogue
(information_schema), so the picture can never disagree with the real schema.

    pip install psycopg2-binary        # and install Graphviz (https://graphviz.org/download/)
    export PGDSN="dbname=atelier_db user=postgres password=YOURPASSWORD host=localhost"
    python3 03_generate_er_diagram.py  # -> er_diagram.png, er_diagram.svg, er_diagram.dot

Notation: crow's foot at the "many" end of each relationship; PK = primary key, FK = foreign key.
"""
import os
import subprocess
import psycopg2

DSN = os.environ.get("PGDSN", "dbname=atelier_db user=postgres password=postgres host=localhost")
OUT = os.path.dirname(os.path.abspath(__file__))
ORDER = ["customers", "orders", "order_items", "payments", "fittings", "variants",
         "products", "collections", "stock_movements"]

COLS = """SELECT table_name, column_name, data_type, is_nullable
          FROM information_schema.columns WHERE table_schema='public' AND table_name = ANY(%s)
          ORDER BY table_name, ordinal_position"""
PKS = """SELECT tc.table_name, kcu.column_name FROM information_schema.table_constraints tc
         JOIN information_schema.key_column_usage kcu USING (constraint_name, table_schema)
         WHERE tc.constraint_type='PRIMARY KEY' AND tc.table_schema='public'"""
FKS = """SELECT tc.table_name, kcu.column_name, ccu.table_name
         FROM information_schema.table_constraints tc
         JOIN information_schema.key_column_usage kcu USING (constraint_name, table_schema)
         JOIN information_schema.constraint_column_usage ccu USING (constraint_name, table_schema)
         WHERE tc.constraint_type='FOREIGN KEY' AND tc.table_schema='public'"""

SHORT = {"character varying": "varchar", "timestamp with time zone": "timestamptz", "character": "char",
         "bigint": "bigint", "integer": "int", "smallint": "smallint", "numeric": "numeric",
         "boolean": "bool", "text": "text"}


def main():
    with psycopg2.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute(COLS, (ORDER,)); cols = cur.fetchall()
        cur.execute(PKS); pks = {(t, c) for t, c in cur.fetchall()}
        cur.execute(FKS); fks = cur.fetchall()
    fk_cols = {(t, c) for t, c, _ in fks}

    dot = ['digraph ER {', ' graph [rankdir=LR, fontname="Helvetica", nodesep=0.35, ranksep=1.0, pad=0.3];',
           ' node [shape=plain, fontname="Helvetica", fontsize=10];',
           ' edge [fontname="Helvetica", fontsize=9, color="#555555", dir=both, arrowhead=tee, arrowtail=crow];']
    for t in ORDER:
        rows = "".join(
            f'<TR><TD ALIGN="LEFT" PORT="{c}">{"<B>PK</B> " if (t,c) in pks else ("FK " if (t,c) in fk_cols else "    ")}'
            f'{c}</TD><TD ALIGN="LEFT"><FONT COLOR="#777777">{SHORT.get(d, d)}</FONT></TD></TR>'
            for tt, c, d, n in cols if tt == t)
        dot.append(f' {t} [label=<<TABLE BORDER="0" CELLBORDER="1" CELLSPACING="0" CELLPADDING="3">'
                   f'<TR><TD COLSPAN="2" BGCOLOR="#1f3a5f"><FONT COLOR="white"><B>{t}</B></FONT></TD></TR>{rows}</TABLE>>];')
    for t, c, parent in fks:
        dot.append(f' {t} -> {parent} [label="{c}"];')
    dot.append('}')

    path = os.path.join(OUT, "er_diagram.dot")
    open(path, "w").write("\n".join(dot))
    for fmt in ("png", "svg"):
        subprocess.run(["dot", f"-T{fmt}", "-Gdpi=150", path, "-o", os.path.join(OUT, f"er_diagram.{fmt}")], check=True)
    print("Wrote er_diagram.png / er_diagram.svg / er_diagram.dot")


if __name__ == "__main__":
    main()
