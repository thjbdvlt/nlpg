from psycopg.sql import SQL, Identifier


def qualify(table) -> Identifier:
    """Table name (optionally with schema)"""
    if not isinstance(table, str):
        return Identifier(*table)
    elif "." in table:
        return Identifier(*(table.split(".")))
    else:
        return Identifier(table)


def make_multi_column_select(table, columns) -> SQL:
    sql_columns = SQL(", ").join([Identifier(i) for i in columns])
    sql_table = qualify(table)
    query = SQL("select {} from {}").format(sql_columns, sql_table)
    return query


def copy_to_multicolumns(table: str, columns: list[str]) -> SQL:
    sql_table = qualify(table)
    sql_columns = SQL(", ").join([Identifier(i) for i in columns])
    query = SQL("copy {} ({}) from stdin").format(sql_table, sql_columns)
    return query


def make_copy_stmt(table: str, columns: list[str]) -> SQL:
    copy_table = qualify(table)
    copy_columns = SQL(", ".join([i for i in columns]))
    sql_copy = SQL("copy {} ({}) from stdin").format(copy_table, copy_columns)
    return sql_copy


def select_values_fk(table: str, cols: list[dict], rev=False) -> SQL:
    """Dynamically build a SQL statement with joins.
    Columns must have following fields:
        {"name": "norm", "is_literal": False}
        {"name": "lemma", "is_literal": True, "value_column": "form"}
    """
    table = qualify(table)
    values = []
    joins = []
    stmt_val = SQL("{table}.{col} as {name}")
    stmt_join = SQL("join {table1} on {table1}.{col1} = {table2}.{col2}")
    for i in cols:
        name = Identifier(i["name"])
        if i["is_literal"] is True:
            s = stmt_val.format(table=table, col=name, name=name)
        else:
            val = Identifier(i.get("value_column", "nom"))
            _id = Identifier("id")
            if rev is False:
                col_val = val
                col_join = _id
            else:
                col_val = _id
                col_join = val
            s = stmt_val.format(table=name, col=col_val, name=name)
            j = stmt_join.format(table1=name, col1=col_join, table2=table, col2=name)
            joins.append(j)
        values.append(s)
    select = SQL("""select {values} from {table} {joins}""")
    values = SQL(", ").join(values)
    joins = SQL("\n").join(joins)
    select = select.format(values=values, table=table, joins=joins)
    return select
