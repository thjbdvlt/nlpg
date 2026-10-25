import re

from nltk.corpus import wordnet as wn
from nltk.corpus.reader.wordnet import Synset
from psycopg import Connection

wn.ensure_loaded()

re_nonw = re.compile(r"[^\w]+")


def make_synset_label(synset: Synset) -> str:
    name = synset.name().strip()
    return re_nonw.sub("_", name)


def make_ltree(paths: list[Synset]) -> str:
    paths = [make_synset_label(i) for i in paths]
    paths = reversed(paths)
    return ".".join(paths)


def get_synset(lemma: str, pos: str, lang: str = "en") -> Synset | None:
    pos = {"noun": "n", "adj": "a", "verb": "v"}.get(pos.lower())
    if pos:
        synsets = wn.synsets(lemma, pos, lang=lang)
        if synsets:
            return synsets[0]


def synset_to_columns(lemma_id: int, synset: Synset) -> dict:
    paths = synset.hypernym_paths()
    paths = [p + [synset] for p in paths]
    paths = [make_ltree(p) for p in paths]
    return {
        "lemma": lemma_id,
        "label": make_synset_label(synset),
        "definition": synset.definition(),
        "examples": synset.examples(),
        "hypernym_paths": paths,
        "lemmas": [i.name() for i in synset.lemmas()],
    }


def synsets(conn: Connection, lang="eng", **_):
    with conn.cursor() as cur:
        cur.execute(
            "SELECT l.id, l.lemma, p.name FROM lemma l JOIN pos p ON p.id = l.pos"
        )
        res = cur.fetchall()
        synsets = [(lid, get_synset(lemma, pos, lang)) for lid, lemma, pos in res]
        synsets = [synset_to_columns(lid, syn) for lid, syn in synsets if syn]
        cur.execute("load 'ltree'")
        cur.execute("truncate nlpg.synset")
        cur.executemany(
            """
        INSERT INTO nlpg.synset (
            lemma,
            label,
            definition,
            examples,
            lemmas,
            hypernym_paths
        )
        VALUES (
            %(lemma)s,
            %(label)s,
            %(definition)s,
            %(examples)s,
            %(lemmas)s,
            (%(hypernym_paths)s::text[])::ltree[]
        );
        """,
            synsets,
        )
