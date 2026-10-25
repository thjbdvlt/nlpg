"""Command Line Interface."""

import argparse
from argparse import ArgumentDefaultsHelpFormatter, ArgumentParser, Namespace

import psycopg
from psycopg import Connection

from .cliopts import opt_cmds, opt_groups
from .nlp import views, xml
from .schema import create_schema

helper = {
    # annotate
    "annotate": "Annotate texts using spacy and insert the resulting annotations.",
    "model": "The name of the spacy pipeline to use, or a path to it.",
    "query_file": "The SQL SELECT query to get texts. The query must returns two rows: one for the text id (`int`), and one for the text content (`text`).",
    "--isword": "The function to be used to distinguish between words and non-word tokens. It's searched into the `@spacy.registry.misc`. See spaCy documentation for information abaout registries.",
    "--batch-size": "Argument for `nlp.pipe(texts)`.",
    "--n-process": "Argument for `nlp.pipe(texts)`.",
    "--batch-size-insert": "If not set or set to `-1`, the annotations are inserted all at once at the end of the annotation processing. Else, the annotations are inserted into the table every N text.",
    "--commit-each-batch": "If `--batch-size-insert` is not `-1`, commit after each insertion. This ensure that if the processing stop before the end, it hasn't to be done from the beginning.",
    "--parser-name": "Name of the parser component in the pipeline.",
    "--morphologizer-name": "Name of the morphologizer component in the pipeline.",
    # schema
    "schema": "Print the definition of a schema to STDOUT.",
    "schema-name": "Name of the schema to be printed.",
    "--table": "Defines the table in which texts are stored. This table is referenced by tables like `sent` or `seg`. The argument of this option must have the form <SCHEMA.TABLE.PK,VAL> where `PK` is the name of a column which type is `int` and is used as a primary key, and where `VAL` is the name of a column used to store `text` values. For example: `public.story.id,content`.",
    # view
    "view": "Generate views.",
    # copy
    "copy": "Copy data from JSON/JSONL files.",
    "files": "Files describing the entities (classes, relations, properties).",
    "--jsonl": "Use JSONL file format (one object per line) instead of JSON. Faster than JSON because the parsing is only done in PostgreSQL, not in Python.",
    "--globexpr": "Add the results of a GLOBEXPR to files. Usefull if the number of files to insert is too high for the command line.",
    # html
    "xml": "Make XML from texts.",
    "copy-vec": "Copy word embeddings into a table.",
    "wordnet": "Add hypernym paths, lemmas and definition from a WordNet.",
}


def add(parser: ArgumentParser, opts: list[list]) -> None:
    """Add an option to a parser."""
    parser.add_argument(*opts[0], **opts[1], help=helper.get(opts[0][-1]))


def name_from_long(opt: list[str]) -> str:
    """Convert argument like `--since-yesterday` to `since_yesterday`."""
    return opt[-1].strip("-").replace("-", "_")


def cli_connect(args: Namespace) -> Connection:
    """Connect to a database."""
    opts = {name_from_long(i[0]) for i in opt_groups["connect"]}
    conninfo = {i: getattr(args, i) for i in opts}
    conn = psycopg.connect(**conninfo)
    return conn


def cli_copy(args: Namespace) -> None:
    """Copy entities from files."""
    from .copy import copy_from

    conn = cli_connect(args)

    try:
        copy_from(conn, **vars(args))
    except Exception:
        conn.close()
        raise
    else:
        conn.commit()
        conn.close()


def cli_copy_vec(args: Namespace) -> None:
    """Load vector from file into a table."""
    from .nlp.vec import copyvec

    conn = cli_connect(args)

    try:
        copyvec(conn, **vars(args))
    except Exception:
        conn.close()
        raise
    else:
        conn.commit()
        conn.close()


def cli_wordnet(args: Namespace):
    """Update the table `nlpg.synset` with WordNet data."""
    from .nlp.wordnet import synsets

    conn = cli_connect(args)
    try:
        synsets(conn, **vars(args))
    except Exception:
        conn.close()
        raise
    else:
        conn.commit()
        conn.close()


def cli_annotate(args: Namespace) -> None:
    """Annotate texts using spacy."""
    from .nlp.text_annotation_v2 import annotate, make_nlp

    conn = cli_connect(args)
    dargs = vars(args)
    try:
        nlp = make_nlp(**dargs)
        annotate(
            conn=conn,
            nlp=nlp,
            stmt_select=args.query_file.read(),
            **dargs,
        )
        with conn.cursor() as cur:
            views.make_views(cur)
    except Exception:
        conn.close()
        raise
    else:
        conn.commit()
        conn.close()


def cli_schema(args: Namespace) -> None:
    """Add schemas to a database."""

    name = args.schema_name
    fk = args.table
    if name == "fk" and not fk:
        raise ValueError("Option `fk` required option `-t`", name)
    conn = cli_connect(args)
    try:
        with conn.cursor() as cur:
            create_schema(cur, name, fk)
    except Exception:
        conn.close()
        raise
    conn.commit()
    conn.close()


def cli_view(args: Namespace) -> None:
    """Generate views."""
    conn = cli_connect(args)
    try:
        with conn.cursor() as cur:
            views.make_views(cur)
    except Exception:
        conn.close()
        raise
    conn.commit()
    conn.close()


def cli_xml(args: Namespace) -> None:
    conn = cli_connect(args)
    try:
        xml.generate_xml_with_spans(conn)
    except Exception:
        conn.close()
        raise
    conn.commit()
    conn.close()


def make_cli_parser():
    """Make the argument parser."""

    parser = argparse.ArgumentParser(
        prog="nlpg",
        formatter_class=ArgumentDefaultsHelpFormatter,
    )
    parser.set_defaults(func=lambda i: None)
    subparsers = parser.add_subparsers(required=True)

    for name, func in [
        ("copy", cli_copy),
        ("annotate", cli_annotate),
        ("schema", cli_schema),
        ("view", cli_view),
        ("xml", cli_xml),
        ("copy-vec", cli_copy_vec),
        ("wordnet", cli_wordnet),
    ]:
        cmd = subparsers.add_parser(
            name,
            help=helper[name],
            formatter_class=ArgumentDefaultsHelpFormatter,
        )
        cmd.set_defaults(func=func)
        cmd_opts_list = opt_cmds[name]
        for group_name in cmd_opts_list:
            group = cmd.add_argument_group(group_name)
            opt_list = opt_groups[group_name]
            for opt in opt_list:
                add(group, opt)
    return parser


def main():
    """Execute the command line program."""

    parser = make_cli_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
