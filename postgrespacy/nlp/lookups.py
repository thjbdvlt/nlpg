from psycopg.sql import Identifier, SQL
from psycopg import Cursor
import spacy
from spacy import Language
from spacy.morphology import Morphology


def feature_to_column_names(labels: list[dict], pos_feat: str) -> dict:
    """Number[psor] -> number_psor"""

    labels = [Morphology.feats_to_dict(i) for i in labels]
    columns = {}
    exclude = {pos_feat, "id", "j", "feats"}
    for i in labels:
        for exc in exclude.intersection(i):
            i.pop(exc)
        for key in i:
            colname = key.lower().replace("[", "_").replace("]", "")
            columns[colname] = key
    return columns


def update_morph_table(
    cur: Cursor, labels: list, pos_feat: str
) -> None:
    """SQLize the FEATS morphological analysis."""

    columns = feature_to_column_names(labels, pos_feat)
    stmt_add_col = SQL(
        "alter table morph add column if not exists {} text;"
    )
    stmt_update = SQL("update morph set {} = lower(trim(j ->> %s))")
    for colname in columns:
        cur.execute(stmt_add_col.format(Identifier(colname)))
        cur.execute(
            stmt_update.format(Identifier(colname)), [columns[colname]]
        )


def insert_select_lookup(
    cur: Cursor, labels: dict, table: str, c_pk: str, c_val: str
) -> dict:
    """Insert missing labels and get a lookup table."""

    table = Identifier(table)
    c_pk = Identifier(c_pk)
    c_val = Identifier(c_val)

    # make the INSERT statement
    sql_insert = """insert into {table} ({val})
    select %s on conflict do nothing"""
    sql_insert = SQL(sql_insert)
    sql_insert = sql_insert.format(table=table, val=c_val)

    # insert missing labels tags in the database
    cur.executemany(sql_insert, [(i,) for i in labels.keys()])

    # make the SELECT statement
    sql_select = """select {val}, {pk} from {table}"""
    sql_select = SQL(sql_select)
    sql_select = sql_select.format(val=c_val, pk=c_pk, table=table)

    # select all labels (VAL, PK) from database
    cur.execute(sql_select)
    res = cur.fetchall()
    lookup_db = dict(res)

    # create the lookup {SPACY_ID: DATABASE_ID}
    return {labels[i]: lookup_db[i] for i in labels}


def get_lookup_dep(
    cur: Cursor, nlp: Language, pipename: str, *args
) -> dict:
    """Get a Lookup {hash: primary key}.

    Note 1: The SQL statement must returns two columns (label, id).
    Note 2: Mostly usefull for parser.
    """

    pipe = nlp.get_pipe(pipename)
    strings = nlp.vocab.strings
    labels = pipe.labels
    labels = {i: strings[i] for i in labels}
    return insert_select_lookup(cur, labels, "dep", "id", "name")


def get_lookup_feats(
    cur: Cursor, nlp: Language, pipename: str, *args
) -> dict:
    """Get a Lookup (dict) for Universal FEATS."""

    pipe = nlp.get_pipe(pipename)
    feats_sep = nlp.vocab.morphology.FEATURE_SEP
    field_sep = nlp.vocab.morphology.FIELD_SEP
    pos_feat = pipe.POS_FEAT
    strings = nlp.vocab.strings
    labels = pipe.labels

    # get label IDs
    pos_pfx = pos_feat + field_sep
    labels = [
        feats_sep.join(
            [i for i in f.split(feats_sep) if not i.startswith(pos_pfx)]
        )
        for f in labels
    ]

    # get label representation as FEATS
    labels = {i: strings[i] for i in labels}

    # add the labels in the morph table
    labels = insert_select_lookup(cur, labels, "morph", "id", "feats")

    # make a column for each FEATS key, and update its value for each row
    update_morph_table(cur, pipe.labels, pos_feat)

    # Empty Morphology hash is mapped to "_" but serialized as ""
    labels[nlp.vocab.strings["_"]] = labels[nlp.vocab.strings[""]]

    return labels


def get_lookup_pos(cur: Cursor, *args) -> dict:
    """Get a Lookup Table for POS tags."""

    pos = spacy.parts_of_speech.IDS
    pos = {i.lower(): pos[i] for i in pos}
    return insert_select_lookup(cur, pos, "pos", "id", "name")
