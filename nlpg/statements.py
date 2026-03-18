from psycopg.sql import SQL, Identifier


def qualify(table):
    """Nom de table et schéma si inclut.

    Args:
        table (str)

    Return (Identifier)
    """

    if not isinstance(table, str):
        return Identifier(*table)
    elif "." in table:
        return Identifier(*(table.split(".")))
    else:
        return Identifier(table)


def make_multi_column_select(table, columns):
    """Construit un statement SELECT qui récupère plusieurs colonnes.

    Args:
        table (str)
        columns (list)

    Returns (SQL)
    """

    sql_columns = SQL(", ").join([Identifier(i) for i in columns])
    sql_table = qualify(table)
    query = SQL("select {} from {}").format(sql_columns, sql_table)
    return query


def copy_to_multicolumns(table, columns):
    """Construit un statement COPY TO avec plusieurs colonnes.

    Args:
        table (str)
        columns (list)

    Returns (SQL)
    """

    sql_table = qualify(table)
    sql_columns = SQL(", ").join([Identifier(i) for i in columns])
    query = SQL("copy {} ({}) from stdin").format(
        sql_table, sql_columns
    )
    return query


def make_copy_stmt(table, columns):
    """Construit un statemnt 'copy' dynamiquement.

    Args:
        table (str)
        columns (list[str])

    Returns (SQL):  le statement COPY ... FROM STDIN.
    """

    copy_table = qualify(table)
    copy_columns = SQL(", ".join([i for i in columns]))
    sql_copy = SQL("copy {} ({}) from stdin").format(
        copy_table, copy_columns
    )
    return sql_copy


def select_values_fk(table, cols, rev=False):
    """Construit dynamiquement un select statement avec des joins.

    Par exemple:
        ```
        select
            lexeme.norme as norme,
            morph.feats as morph
        from lexeme
        join morph on morph.id = lexeme.id
        ```

    Args:
        table (str):  le nom de la table de base.
        cols (list[dict]):  les informations sur les colonnes.

    Les dicts doivent avoir les champs suivante:
        {"name": "norme", "is_literal": False}
        {"name": "lemme", "is_literal": True, "value_column": "graphie"}
    """

    table = qualify(table)
    values = []
    joins = []
    stmt_val = SQL("{table}.{col} as {name}")
    stmt_join = SQL(
        "join {table1} on {table1}.{col1} = {table2}.{col2}"
    )
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
            j = stmt_join.format(
                table1=name, col1=col_join, table2=table, col2=name
            )
            joins.append(j)
        values.append(s)
    select = SQL("""select {values} from {table} {joins}""")
    values = SQL(", ").join(values)
    joins = SQL("\n").join(joins)
    select = select.format(values=values, table=table, joins=joins)
    return select
