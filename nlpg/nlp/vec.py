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


def copyvec(
    conn: Connection,
    file: str | KeyedVectors,
    schema: str,
    table: str,
    binary: bool = True,
    **_,
):
    if isinstance(file, KeyedVectors):
        vectors = file
    else:
        vectors = KeyedVectors.load_word2vec_format(file, binary=binary)
    dims = Literal(int(vectors.vector_size))
    conn.execute("create extension if not exists vector")
    conn.execute("load 'vector'")
    register_vector(conn)
    with conn.cursor() as cur:
        table = Identifier(schema, table)
        stmt = SQL("create table {} (key text, vec vector({}))")
        stmt = stmt.format(table, dims)
        cur.execute(stmt)
        stmt = SQL("copy {} from stdin with (format binary)")
        stmt = stmt.format(table)
        with cur.copy(stmt) as copy:
            copy.set_types(["text", "vector"])
            for i in tqdm(itervec(vectors)):
                copy.write_row(i)
        stmt = SQL("create index on {} (key)").format(table)
        cur.execute(stmt)


def copy_vec_lemma(conn: Connection, file: str | KeyedVectors, binary: bool = True, **_):
    vectors = (
        file
        if isinstance(file, KeyedVectors)
        else KeyedVectors.load_word2vec_format(file, binary=binary)
    )
    conn.execute("create extension if not exists vector")
    conn.execute("load 'vector'")
    register_vector(conn)
    with conn.cursor() as cur:
        cur.execute("select lemma from lemma")
        lemmas = [i[0] for i in cur.fetchall()]
        lemmas = [i for i in lemmas if i in vectors]
        stmt = SQL("alter table nlpg.lemma add column vector vector({})")
        stmt = stmt.format(Literal(int(vectors.vector_size)))
        cur.execute(stmt)
        data = [(vectors[i], i) for i in lemmas]
        cur.executemany("update nlpg.lemma set vector = %s where lemma = %s", data)
        stmt = SQL("create index on lemma (vector)")
