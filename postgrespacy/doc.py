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
    # copy-vec
    "copy-vec": "Copy word embeddings into a table.",
}
