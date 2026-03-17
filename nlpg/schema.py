import pkgutil
from psycopg.sql import SQL, Identifier
from psycopg import Cursor


SCHEMA_EAV = "eav"
SCHEMA = "nlpg"
TABLE_IMPORT = "_entity"
TABLE_ANNOTES = "nlpg._textobj"
TABLE_CONFIG = "_config"
SCHEMAS = (SCHEMA, SCHEMA_EAV)
SCHEMA_OPTS = (SCHEMA, SCHEMA_EAV, "fk", "both")


def get(filename: str) -> str:
    """Get the content of a SQL file in the data directory."""
    return pkgutil.get_data(__name__, f"data/{filename}.sql").decode()


def make_foreign_key(
    cur: Cursor, text: str = "eav.string.id,val"
) -> str:
    """Generate the foreign keys from tables `sent`, `span`, `seg` to the table containing textual data. (e.g. `eav.string`)."""
    fk = text.strip().split(".")
    if not len(fk) == 3:
        raise ValueError(
            "couldn't parse: ", text, "\n\n(SCHEMA.TABLE.PK,VAL)"
        )
    schema, table, pk = fk
    pk, val = pk.split(",")
    stmt_config = SQL("select {}._set_config(%s, %s)")
    stmt_config = stmt_config.format(Identifier(SCHEMA))
    for i in [
        ("string_table", table),
        ("string_schema", schema),
        ("string_id", pk),
        ("string_val", val),
    ]:
        cur.execute(stmt_config, i)
    stmt_base = SQL(
        "ALTER TABLE ONLY {}\n    "
        "ADD CONSTRAINT {} FOREIGN KEY (string) REFERENCES {} ({})"
    )
    # for i in ["sent", "seg", "span"]:
    for i in ["par", "seg", "span"]:
        constraint_name = Identifier(f"{i}_string_fk")
        qualified_i = Identifier(SCHEMA, i)
        stmt = stmt_base.format(
            qualified_i,
            constraint_name,
            Identifier(schema, table),
            Identifier(pk),
        )
        cur.execute(stmt)


def create_schema(cur: Cursor, name: str, fk: str) -> None:
    """Add one or many schemas to a database."""
    if name not in SCHEMA_OPTS:
        raise ValueError("Unknown schema name:", name)
    for i in SCHEMAS:
        if name in (i, "both"):
            cur.execute(get(i))
    if name in ("both", "fk"):
        if not fk:
            fk = "eav.string.id"
        make_foreign_key(cur, fk)
