"""A module to build XML tags from spans."""

from psycopg import Cursor, Connection
from psycopg.sql import SQL, Identifier
from ..schema import SCHEMA
from ..util import get_config_value
import nh3
from lxml.html import Element, tostring
from lxml import etree
import tqdm


def make_tags_from_span_attrs(tag: str, attrs: dict) -> tuple[str, str]:
    """Make tags for a span."""
    el = Element(tag, attrs)
    s = tostring(el).decode()
    if s.count(">") == 1:
        return s, ""
    else:
        pos = s.index(">")
        return s[: pos + 1], s[pos + 1 :]


def add_a_span_as_tag(
    s: list,
    start: int,
    length: int,
    tag: str,
    attrs: dict,
) -> None:
    "Add a span as XML tags."
    start_tag, end_tag = make_tags_from_span_attrs(tag, attrs)
    end = start + length
    if len(s) <= start:
        s.append(start_tag)
    else:
        s[start] = start_tag + s[start]
    if len(s) <= end:
        s.append(end_tag)
    else:
        s[end - 1] = s[end - 1] + end_tag


def add_spans_as_tags(s: str, spans: tuple[int, int, dict]):
    """Add many spans as tags to a string."""
    s = [" "] + list(s)
    for i in spans:
        add_a_span_as_tag(s, i["idx"], i["len"], i["tag"], i["attrs"])
    return nh3.clean("".join(s).replace("\n", "<br/>\n"))


def make_stmt_get_all_texts(cur: Cursor) -> SQL:
    """Make the statement to get all texts."""
    conf = {}
    keys = ["string_table", "string_schema", "string_id", "string_val"]
    for i in keys:
        k = i.replace("string_", "")
        conf[k] = Identifier(get_config_value(cur, i))
    stmt_get = SQL("""WITH sp AS (
    SELECT string, jsonb_agg(to_jsonb(xspan)) AS spans
    FROM xspan GROUP BY string
) SELECT {id}, {val}, coalesce(sp.spans, '[]'::jsonb) FROM {table} AS t
LEFT OUTER JOIN sp ON t.{id} = sp.string""").format(**conf)
    return stmt_get


def generate_xml_with_spans(
    conn: Connection,
    stmt_get: str = None,
) -> None:
    """Format texts as XML, encoding spans."""
    cur_fetch = conn.cursor()
    cur_send = conn.cursor()
    stmt_get = make_stmt_get_all_texts(cur_fetch)
    table = Identifier(SCHEMA, "markup")
    stmt_copy = SQL("COPY {} (id, text) FROM STDIN").format(table)
    cur_send.execute(SQL("TRUNCATE {}").format(table))
    cur_fetch.execute(stmt_get)
    with cur_send.copy(stmt_copy) as copy:
        for id, text, spans in tqdm.tqdm(cur_fetch):
            text = add_spans_as_tags(text, spans)
            row = (id, text)
            copy.write_row(row)
    cur_send.close()
    cur_fetch.close()


def xmltodict(s) -> dict:
    root = etree.fromstring(s)
    text = []
    tags = []

    def nonone(x: etree._Element) -> None:
        """Replace `None` values to avoid errors later."""

        def fn(e: etree._Element) -> str:
            e.text = "" if e.text is None else e.text
            e.tail = "" if e.tail is None else e.tail

        for i in x.iterdescendants():
            fn(i)
        fn(x)  # (`x` is not a descendant of itself.)
        return None

    def idx(el: etree._Element, n: int) -> int:
        # add text to total text
        text.append(el.text)

        # la plupart des informations sont connues au début de l'appel de la fonction: le tag, le 'debut' et les attributs. seul 'fin' doit être trouvé par la suite. (même si, en réalité, on pourrait aussi simplement sérialiser avec le paramètre `methode='text'`, mais cela ajoute une sérialisation inutile et je ne sais pas si la 'tail' est dedans.)
        x = {"tag": el.tag, "start": n, "attrs": dict(el.attrib)}
        n += len(el.text)

        # appel recursif de la fonction sur les éléments dans l'élément actuel. il est important de retourner 'n' puisque sinon 'n' n'est pas modifié (pas la même portée).
        for sub in el:
            n = idx(sub, n)

        # ajouter la tail au texte total.
        text.append(el.tail)

        # après avoir calculer la longueur de tous les élements dans l'élement actuel, on connait la valeur de 'n' (le caractère actuel dans le calcul).
        x["end"] = n
        # important: ajouter la longueur de la tail à n seulement après avoir assigné 'n' au fin, car la tail est en dehors de l'élément.
        n += len(el.tail)

        # ajouter aux tags
        tags.append(x)

        # retourne n, pour passer la valeur de 'n' dans les appels récursifs.
        return n

    nonone(root)  # remplace les valeurs 'None' par '""'
    idx(root, 0)  # la fonction principale
    text = "".join([i for i in text if i is not None])
    res = {"text": text, "tags": tags, "xml": s}
    return res
