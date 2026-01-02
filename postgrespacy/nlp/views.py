from psycopg import Cursor
from psycopg.sql import SQL, Identifier
from ..schema import SCHEMA
from ..util import get_config_value


def get_morph_features_list(cur: Cursor) -> SQL:
    """Get a comma-separated list of all columns of morph table."""
    cur.execute(SQL("select * from morph limit 0"))
    morph_cols = [i[0] for i in cur.description]
    morph_cols = set(morph_cols) - {"id", "feats", "j"}
    morph_cols = [Identifier("morph", i) for i in morph_cols]
    morph_cols = SQL(",").join(morph_cols)

    return morph_cols


def create_view_morph_as_columns(
    cur: Cursor, viewname: str, stmt: SQL
) -> None:
    """Dynamically create a view with morphological features as columns."""

    viewname = Identifier(SCHEMA, viewname)
    cur.execute(SQL("drop view if exists {} cascade").format(viewname))
    cur.execute(stmt.format(viewname, get_morph_features_list(cur)))


def make_views(cur: Cursor) -> None:
    """Make the views word_, lexeme_ and sent_."""
    make_view_par(cur)
    make_view_sent(cur)
    create_view_morph_as_columns(
        cur,
        "word_",
        SQL("""create view {} as
select
    sent.string,
    sent.id as sent,
    sent.par,
    word.i as i,
    word.s as s,
    word.tspace as tspace,
    word.idx,
    word.len,
    lexeme.norm as norm,
    lemma.str as lemma,
    pos.name as pos,
    word.head as head,
    dep.name as dep,
    {}
from
    word
    join sent on sent.id = word.sent
    join lexeme on lexeme.id = word.lexeme
    join lemma on lemma.id = lexeme.lemma
    join pos on pos.id = lexeme.pos
    join morph on morph.id = lexeme.morph
    join dep on dep.id = word.dep;
    """),
    )
    create_view_morph_as_columns(
        cur,
        "token_",
        SQL("""create view {} as
select
    sent.string,
    sent.id as sent,
    sent.par,
    word.i as i,
    word.s as s,
    word.tspace as tspace,
    word.idx,
    word.len,
    lexeme.norm as norm,
    lemma.str as lemma,
    pos.name as pos,
    word.head as head,
    dep.name as dep
from
    word
    join sent on sent.id = word.sent
    join lexeme on lexeme.id = word.lexeme
    join lemma on lemma.id = lexeme.lemma
    join pos on pos.id = lexeme.pos
    join dep on dep.id = word.dep
union
select
    sent.string,
    sent.id as sent,
    sent.par,
    token.i as i,
    token.s as s,
    token.tspace as tspace,
    token.idx,
    token.len,
    '' as norm,
    '' as lemma,
    '' as pos,
    -1 as head,
    '' as dep
from
    only token
    join sent on sent.id = token.sent
    """),
    )
    create_view_morph_as_columns(
        cur,
        "lexeme_",
        SQL("""CREATE VIEW {} AS
SELECT
    lexeme.id,
    lexeme.norm,
    lemma.str AS lemma,
    pos.name AS pos,
    {}
FROM
    lexeme
    JOIN pos ON pos.id = lexeme.pos
    JOIN lemma ON lemma.id = lexeme.lemma
    JOIN morph ON morph.id = lexeme.morph
    """),
    )

    make_function_concordances(cur)


def make_view_sent(cur: Cursor) -> None:
    """Make the view "sent_"."""

    schema = get_config_value(cur, "string_schema")
    table = get_config_value(cur, "string_table")
    col_id = get_config_value(cur, "string_id")
    col_val = get_config_value(cur, "string_val")

    stmt = SQL("""CREATE OR REPLACE VIEW {viewname} AS
SELECT
    sent.string,
    sent.par,
    sent.id,
    sent.i,
    substring({column_val}, sent.idx, sent.len) as s
from sent
    join {table_name} on {column_id} = sent.string;
    """).format(
        viewname=Identifier(SCHEMA, "sent_"),
        column_val=Identifier(table, col_val),
        table_name=Identifier(schema, table),
        column_id=Identifier(table, col_id),
    )
    cur.execute(stmt)


def make_view_par(cur: Cursor) -> None:
    """Make the view 'par_'."""
    schema = get_config_value(cur, "string_schema")
    table = get_config_value(cur, "string_table")
    col_id = get_config_value(cur, "string_id")
    col_val = get_config_value(cur, "string_val")
    stmt = SQL("""CREATE OR REPLACE VIEW {viewname} AS
SELECT
    s.id as string,
    {t}.idx,
    {t}.len,
    {t}.id,
    {t}.i,
    substring(s.{column_val}, {t}.idx, {t}.len) as text
from {t}
    join {table_name} as s on s.{column_id} = {t}.string;
    """).format(
        viewname=Identifier(SCHEMA, "par_"),
        t=Identifier(SCHEMA, "par"),
        column_val=Identifier(col_val),
        table_name=Identifier(schema, table),
        column_id=Identifier(col_id),
    )
    cur.execute(stmt)


def make_function_concordances(cur: Cursor) -> None:
    """Make functions that depends on views.."""

    cur.execute(
        SQL("""CREATE OR REPLACE FUNCTION
{} (word_, int = 100, int = 50)
RETURNS text
LANGUAGE sql
AS $function$
SELECT
    substring(regexp_replace(
        CASE WHEN $1.idx < $3 THEN
            lpad('', ($3 + 1) - $1.idx, ' ') || string.val
        ELSE
            string.val
        END, '[\\n\\t]', ' ', 'g'),
        greatest ($1.idx - $3, 1),
        $2
    )
FROM
    string
WHERE
    $1.string = string.id
$function$;""").format(Identifier(SCHEMA, "align_concordance"))
    )

    cur.execute(
        SQL("""CREATE OR REPLACE FUNCTION
{} (text, int = 100, int = 50)
RETURNS TABLE (string_id int, context text)
LANGUAGE sql
AS $function$
SELECT
    w.string, {} (w, $2, $3)
    FROM word_ w WHERE lemma = $1
$function$;""").format(
            Identifier(SCHEMA, "concordance"),
            Identifier(SCHEMA, "align_concordance"),
        )
    )
