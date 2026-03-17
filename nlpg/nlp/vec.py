from pgvector.psycopg import register_vector
from psycopg import Connection
from psycopg.sql import SQL, Identifier, Literal
from gensim.models import KeyedVectors
from tqdm import tqdm


def itervec(vectors):
    for k, v in zip(vectors.index_to_key, vectors):
        if "\x00" in k:
            k = k.replace("\x00", "")
        yield (k, v)


def copyvec(
    conn: Connection,
    file: str,
    schema: str,
    table: str,
    binary: bool = True,
    **kwargs,
):
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
