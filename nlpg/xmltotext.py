from psycopg import Connection
from psycopg.sql import SQL
from psycopg.rows import namedtuple_row
import tqdm
from .extract_tags import extract_tags


def tags_to_xtag(conn: Connection):
    """Extract start/end tags from XML."""
    stmt_get = SQL("""
        with x as (
            select entity, type from xml
            except
            select entity, type from string
        )
        select type, entity, val from xml
        join x using (entity, type)
    """)
    stmt_insert = SQL("""
        insert into string (entity, type, val)
        select %s, %s, %s on conflict do nothing returning id
    """)
    stmt_copy_tags = "copy xtag (sid, idxxml, idxtext, len, s) from stdin"
    cur_get = conn.cursor(row_factory=namedtuple_row)
    cur_send = conn.cursor(row_factory=namedtuple_row)
    cur_get.execute(stmt_get)
    with cur_send.copy(stmt_copy_tags) as copy:
        for i in tqdm.tqdm(cur_get):
            idx, tags, text = extract_tags(i.val)
            for (idxtext, idxxml, length), s in zip(idx, tags):
                row = (i.entity, idxxml, idxtext, length, s)
                copy.write_row(row)
    conn.commit()
    for i in (cur_get, cur_send):
        i.close()
