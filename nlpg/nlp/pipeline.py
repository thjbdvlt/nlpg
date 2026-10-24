import spacy
from spacy.language import Language


@Language.component("sent_on_newline")
def newline_is_new_sentence(doc):
    for token in doc:
        if token.text == "\n":
            token.is_sent_start = True
    return doc


def load_small_model():
    nlp = spacy.load("fr_core_news_sm")
    nlp.add_pipe("sent_on_newline", first=True)
    nlp.add_pipe("jusqucy_ttypifier", first=True)
    return nlp
