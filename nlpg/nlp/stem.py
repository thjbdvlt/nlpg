from nltk.stem.snowball import SnowballStemmer
from psycopg import Connection


def stem_lemmas(conn: Connection, lang="english", stemmer_name="snowball", **_):
    # TODO: other Stemmers, such as Portner
    stemmer = SnowballStemmer(lang)
    with conn.cursor() as cur:
        cur.execute("SELECT id, lemma FROM lemma")
        res = cur.fetchall()
        res = [(stemmer.stem(lemma), id) for id, lemma in res]
        cur.executemany("UPDATE lemma set stem = %s where id = %s", res)
