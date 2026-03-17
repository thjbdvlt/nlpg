import json
import glob
import tqdm
from psycopg.sql import SQL, Identifier
from psycopg.copy import Copy
from psycopg import Connection
from .schema import TABLE_IMPORT, SCHEMA_EAV
from typing import Iterator, Optional
from .xmltotext import tags_to_xtag


def _copy_from_json(
    copy: Copy, files: Iterator, dynamic_ncols: bool = False
) -> None:
    """Copy from JSON files."""

    for filepath in tqdm.tqdm(files, dynamic_ncols=dynamic_ncols):
        with open(filepath, "r") as file:
            array = json.load(file)
            assert isinstance(array, list)
            for obj in array:
                copy.write_row((json.dumps(obj, ensure_ascii=False),))


def _copy_from_json_l(
    copy: Copy, files: Iterator, dynamic_ncols: bool = False
) -> None:
    """Copy from JSONL files (one JSON object per line)."""

    for filepath in tqdm.tqdm(files, dynamic_ncols=dynamic_ncols):
        with open(filepath, "r") as file:
            for line in file:
                copy.write_row((line.strip(),))


def copy_from(
    conn: Connection,
    files: Iterator,
    jsonl: bool = False,
    noinsert: bool = False,
    globexpr: Optional[str] = None,
    dynamic_ncols: bool = False,
    **kwargs,
):
    """Copy from JSON/JSONL files into the database."""

    cur = conn.cursor()
    schema = Identifier(SCHEMA_EAV)
    table = Identifier(TABLE_IMPORT)
    stmt = SQL("copy {}.{} (j) from stdin").format(schema, table)
    with cur.copy(stmt) as copy:
        func = _copy_from_json_l if jsonl else _copy_from_json
        if globexpr:
            files.extend(glob.glob(globexpr))
        func(copy, files, dynamic_ncols=dynamic_ncols)
    if not noinsert:
        cur.execute(SQL("call {}.importer();").format(schema))
        tags_to_xtag(conn)
    # cur.close()
