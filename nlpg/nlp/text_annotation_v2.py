from psycopg import Connection
import spacy
from spacy import Language
from spacy.tokens import Token, Doc
import tqdm
from collections import namedtuple
from typing import Iterator
from ..errors import InvalidRowType
from ..schema import TABLE_ANNOTES
from ..statements import make_copy_stmt
from ..util import check_row_types, make_log_func_tqdm
from .lookups import get_lookup_dep, get_lookup_feats, get_lookup_pos

TYPEID_WORD = 1
TYPEID_NONWORD = 0
TYPEID_SENT = -1
TYPEID_PARAGRAPH = -2
# TODO:
# -3    span
# -4    ent
# ...

RowToken = namedtuple(
    "rowtoken",
    [
        "text_id",
        "par_i",
        "sent_i",
        "type",
        "i",
        "idx",
        "len",
        "s",
        "tspace",
        "norm",
        "pos",
        "morph",
        "lemma",
        "dep",
        "head",
        "userdata",
    ],
    defaults=[None] * 7,
)


def token_sent_i(doc: Doc) -> Iterator[int]:
    """Get Sentence Indexes (one per token).

    This behaves like `[token.sent.i for i in doc]` (which doesn't exist).
    """

    for n, sent in enumerate(doc.sents, 1):
        sent_len = len(sent)
        for i in range(sent_len):
            yield n


def get_sents(
    text_id: int, par_i: int, par_idx: int, doc: Doc
) -> Iterator[RowToken]:
    """Get a Tuple (RowToken) for each Sentence."""

    for sent_i, i in enumerate(doc.sents, 1):
        yield RowToken(
            text_id=text_id,
            par_i=par_i,
            sent_i=sent_i,
            type=TYPEID_SENT,
            i=sent_i,
            idx=par_idx + i.start_char + 1,
            len=i.end_char - i.start_char,
            s=None,
            tspace=0,
            norm=None,
            pos=None,
            morph=None,
            lemma=None,
            dep=None,
            head=None,
            userdata=None,
        )


def get_tokens(
    text_id: int,
    pid: int,
    pidx: int,
    doc: Doc,
    lookup_pos: dict,
    lookup_feats: dict,
    lookup_dep: dict,
) -> Iterator[RowToken]:
    """Get a Tuple for each Token in a Doc."""

    for sent, token in zip(token_sent_i(doc), doc):
        idx = pidx + token.idx + 1
        i = token.i + 1
        yield (
            RowToken(
                text_id=text_id,
                par_i=pid,
                sent_i=sent,
                type=TYPEID_WORD,
                i=i,
                idx=idx,
                len=len(token),
                s=token.text,
                tspace=len(token.whitespace_),
                # word-specific features
                norm=token.norm_,
                pos=lookup_pos[token.pos],
                morph=lookup_feats[token.morph.key],
                lemma=token.lemma_,
                dep=lookup_dep[token.dep],
                head=token.head.i + 1,
                userdata=None,
            )
            if token._.isword
            else RowToken(
                text_id=text_id,
                par_i=pid,
                sent_i=sent,
                type=TYPEID_NONWORD,
                i=i,
                idx=idx,
                len=len(token),
                s=token.text,
                tspace=len(token.whitespace_),
                # no word-specific features
                norm=None,
                morph=None,
                lemma=None,
                dep=None,
                head=None,
                userdata=None,
            )
        )


def doc_to_row(
    text_id: int,
    pid: int,
    pidx: int,
    plen: int,
    doc: Doc,
    lookup_pos: dict,
    lookup_feats: dict,
    lookup_dep: dict,
) -> Iterator[RowToken]:
    """Produce Row to be inserted in the database from a Doc."""
    for i in get_tokens(
        text_id, pid, pidx, doc, lookup_pos, lookup_feats, lookup_dep
    ):
        yield i
    for i in get_sents(text_id, pid, pidx, doc):
        yield i
    yield RowToken(
        text_id=text_id,
        par_i=pid,
        sent_i=None,
        type=TYPEID_PARAGRAPH,
        i=pid,
        idx=pidx + 1,
        len=plen,
        s=None,
        tspace=0,
        norm=None,
        morph=None,
        pos=None,
        head=None,
        dep=None,
        userdata=None,
    )
    # TODO: spans
    # TODO: ents


def split_texts_into_paragraphs(
    texts: Iterator[tuple], paragraph_delimiter: str
) -> Iterator[tuple[str, tuple[int, int, int, bool]]]:
    """Split a text into paragraphs, tracking character indexing."""
    for text, did in texts:
        pars = text.split(paragraph_delimiter)
        n_pars = len(pars)
        pidx = 0
        for pid, p in enumerate(pars, 1):
            plen = len(p)
            new = True if pid == 1 else False
            yield p, (did, pid, pidx, plen, new)
            pidx += plen
            if pid < n_pars:
                pidx += 2


def annotate(
    conn: Connection,
    stmt_select: str,
    nlp: Language,
    morphologizer_name: str = "morphologizer",
    parser_name: str = "parser",
    batch_size_insert: int = -1,
    commit_each_batch: bool = True,
    dynamic_ncols: bool = False,
    batch_size: int = 1000,
    n_process: int = 1,
    paragraph_delimiter: str = "\n\n",
    **kwargs,
):
    """Process texts from the database and send annotations back."""

    cur_fetch = conn.cursor()
    cur_send = conn.cursor()

    l_feats = get_lookup_feats(cur_fetch, nlp, morphologizer_name)
    l_dep = get_lookup_dep(cur_fetch, nlp, parser_name)
    l_pos = get_lookup_pos(cur_fetch)

    cur_fetch.execute(stmt_select)

    ok_types = [{"text", "char", "varchar"}, {"int2", "int4", "int8"}]
    if not check_row_types(cur_fetch, ok_types):
        raise InvalidRowType(cur_fetch, ok_types)

    texts = split_texts_into_paragraphs(cur_fetch, paragraph_delimiter)

    docs = nlp.pipe(
        texts=texts,
        as_tuples=True,
        batch_size=batch_size,
        n_process=n_process,
    )
    stmt_send = make_copy_stmt(TABLE_ANNOTES, RowToken._fields)

    def annote_some_texts(cur_send, docs, pinfo) -> bool:
        """Annote a few texts and put outputs into the database."""
        n = 0
        with cur_send.copy(stmt_send) as copy:
            for doc, (text_id, pid, pidx, plen, new) in docs:
                for row in doc_to_row(
                    text_id,
                    pid,
                    pidx,
                    plen,
                    doc,
                    l_pos,
                    l_feats,
                    l_dep,
                ):
                    copy.write_row(row)
                if new:
                    pinfo.update(1)
                n += 1
                if n == batch_size_insert:
                    return True
            return False

    total = cur_fetch.rowcount
    with tqdm.trange(total, dynamic_ncols=dynamic_ncols) as pinfo:
        conn.add_notice_handler(make_log_func_tqdm(pinfo))
        state = True
        while state:
            pinfo.set_description("Annotating...")
            state = annote_some_texts(cur_send, docs, pinfo)
            cur_send.execute("select insert_annotations(1)")
            if commit_each_batch:
                conn.commit()
    pinfo.set_description("End of annotions.")
    cur_send.execute("select insert_annotations(1)")
    cur_send.close()
    cur_fetch.close()


def make_nlp(model: str, isword: str = None, **kwargs) -> Language:
    """Load and set up the pipeline."""
    nlp = spacy.load(model)
    extname = "isword"
    if not Token.has_extension(extname):
        if isword:
            func = spacy.registry.misc.get(isword)
            Token.set_extension(extname, getter=func)
        else:
            Token.set_extension(extname, getter=lambda i: True)
    return nlp
