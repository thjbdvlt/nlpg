"""Command Line Interface."""

import argparse
import psycopg
from argparse import (
    Namespace,
    ArgumentParser,
    ArgumentDefaultsHelpFormatter,
)
from psycopg import Connection
from . import doc
from .schema import create_schema
from .cliopts import opt_groups, opt_cmds
from .nlp import views, xml


def add(parser: ArgumentParser, opts: list[list]) -> None:
    """Add an option to a parser."""
    parser.add_argument(
        *opts[0], **opts[1], help=doc.helper.get(opts[0][-1])
    )


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


def cli_annotate(args: Namespace) -> None:
    """Annotate texts using spacy."""
    from .nlp.text_annotation_v2 import make_nlp, annotate

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
    ]:
        cmd = subparsers.add_parser(
            name,
            help=doc.helper[name],
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
