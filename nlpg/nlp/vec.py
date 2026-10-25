import gensim.downloader
from gensim.models import KeyedVectors
from pgvector.psycopg import register_vector
from psycopg import Connection
from psycopg.sql import SQL, Identifier, Literal
from tqdm import tqdm


def itervec(vectors):
    for k, v in zip(vectors.index_to_key, vectors):
        if "\x00" in k:
            k = k.replace("\x00", "")
        yield (k, v)


def load(
    file: str | KeyedVectors,
    gensim_download: bool,
    binary: bool,
    **_,
) -> KeyedVectors:
    if gensim_download:
        return gensim.downloader.load(file)
    if isinstance(file, KeyedVectors):
        return file
    return KeyedVectors.load_word2vec_format(file, binary=binary)


def copy_vec_all(conn: Connection, vectors: KeyedVectors, **_):
    dims = Literal(int(vectors.vector_size))
    with conn.cursor() as cur:
        stmt = SQL("create table nlpg.vec (key text, vec vector({}))")
        stmt = stmt.format(dims)
        cur.execute(stmt)
        stmt = SQL("copy nlpg.vec from stdin with (format binary)")
        with cur.copy(stmt) as copy:
            copy.set_types(["text", "vector"])
            for i in tqdm(itervec(vectors)):
                copy.write_row(i)
        cur.execute(SQL("create index on nlpg.vec (key)"))


def copy_vec_lemma(conn: Connection, table: str, vectors: KeyedVectors, **_):
    column = {"lemma": "lemma", "lexeme": "norm"}[table]
    column, table = Identifier(column), Identifier(table)
    with conn.cursor() as cur:
        # fetch lemma or norms, and filter to keep only ones with vectors
        cur.execute(SQL("select {} from {}").format(column, table))
        lemmas = [i[0] for i in cur.fetchall()]
        lemmas = [i for i in lemmas if i in vectors]
        # drop existing `vector` columns and recreate it.
        # this is necessary because the dimensions must differ.
        stmt = SQL("alter table nlpg.{} drop column if exists vector").format(table)
        cur.execute(stmt)
        dims = Literal(int(vectors.vector_size))
        stmt = SQL("alter table nlpg.{} add column vector vector({})")
        cur.execute(stmt.format(table, dims))
        # update the table
        stmt = SQL("update nlpg.{} set vector = %s where {} = %s").format(table, column)
        cur.executemany(stmt, [(vectors[i], i) for i in lemmas])
        # build the index
        cur.execute(SQL("create index on {} (vector)").format(table))


def copyvec(conn, table, *args, **kwargs):
    conn.execute("create extension if not exists vector")
    conn.execute("load 'vector'")
    register_vector(conn)
    if table in ["lemma", "lexeme"]:
        func = copy_vec_lemma
    elif table == "vec":
        func = copy_vec_all
    else:
        raise ValueError("`table` argument must be 'lemma', 'vec' or 'lexeme'.")
    func(conn=conn, vectors=load(**kwargs), table=table, *args, **kwargs)
