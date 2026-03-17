from .util import CallableDict
from .schema import SCHEMA_OPTS
from argparse import FileType


pos_many_str = CallableDict(nargs="*", action="store", type=str)
pos_str = CallableDict(action="store", type=str)
pos_file = pos_str(type=FileType("r"))
pos_many_int = pos_many_str(type=int)
str_nonopt = CallableDict(action="store", required=True, type=str)
store_true = CallableDict(action="store_true", default=False)
str_opt = str_nonopt(required=False, default=None)
store_int_opt = str_opt(type=int)

opt_groups = {
    "connect": [
        [["-d", "--dbname"], str_nonopt],
        [["-p", "--port"], str_opt],
        [["-H", "--host"], str_opt],
        [["-U", "--user"], str_opt],
        [["-P", "--password"], str_opt],
    ],
    "tqdm": [
        [["-D", "--dynamic-ncols"], store_true],
    ],
    "annotate": [
        [["model"], pos_str],
        [["query_file"], pos_file],
        [["-w", "--isword"], str_opt],
        [["--commit-each-batch"], store_true],
        [["--batch-size-insert"], store_int_opt(default=-1)],
        [["--n-process"], store_int_opt(default=1)],
        [["--batch-size"], store_int_opt(default=100)],
        [["--morphologizer-name"], str_opt(default="morphologizer")],
        [["--parser-name"], str_opt(default="parser")],
        [["--paragraph-delimiter"], str_opt(default="\n\n")],
    ],
    "copy": [
        [["files"], pos_many_str],
        [["-l", "--jsonl"], store_true],
        [["-g", "--globexpr"], str_opt],
        [["-x", "--xml"], store_true],
    ],
    "copy-vec": [
        [["file"], pos_str],
        [["-t", "--table"], str_opt(default="vec")],
        [["-s", "--schema"], str_opt(default="nlpg")],
        [["-b", "--binary"], store_true],
    ],
    "schema": [
        [
            ["schema_name"],
            pos_str(nargs="?", default="both", choices=SCHEMA_OPTS),
        ],
        [
            ["-t", "--table"],
            str_opt(
                metavar="<schema.table.id,text>",
                default="eav.string.id,val",
            ),
        ],
    ],
}

opt_cmds = {
    "annotate": ["annotate", "tqdm", "connect"],
    "copy": ["copy", "tqdm", "connect"],
    "copy-vec": ["copy-vec", "connect"],
    "schema": ["schema", "connect"],
    "view": ["connect"],
    "xml": ["connect"],
}
