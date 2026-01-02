from spacy.language import Language
import spacy


@Language.component("sent_on_newline")
def newline_is_new_sentence(doc):
    """Ajoute des sentence boundaries sur les nouvelles lignes.

    Args:
        doc (Doc)
    Returns (Doc)
    """

    for token in doc:
        if token.text == "\n":
            token.is_sent_start = True
    return doc


def load_small_model():
    """Charger un modèle petit et simple, pour des tests.

    Returns (Language):  le modèle pour l'analyse avec spacy.
    """

    nlp = spacy.load("fr_core_news_sm")
    nlp.add_pipe("sent_on_newline", first=True)
    nlp.add_pipe("jusqucy_ttypifier", first=True)
    return nlp
