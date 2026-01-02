from psycopg import Cursor
from psycopg.errors import Diagnostic
from psycopg.sql import SQL, Identifier
from typing import Callable, Union
import tqdm
from .schema import SCHEMA


def get_result_row_types(cursor: Cursor) -> list[str]:
    """Get the names of the datatypes returned by last `Cursor.execute(...)`."""

    get_type = cursor.connection.adapters.types.get
    return [get_type(i[1]).name for i in cursor.description]


def check_row_types(
    cursor: Cursor, types_names: Union[list[str], list[list[str]]]
) -> bool:
    """Check that `Cursor.execute(...)` returned correct types."""

    res_types_names = get_result_row_types(cursor)
    for actual, correct in zip(res_types_names, types_names):
        if isinstance(correct, (list, tuple, set)):
            if actual not in correct:
                return False
        else:
            if actual != correct:
                return False
    return True


def roundup(a: float) -> int:
    """Round up an `int`."""
    if a < 0.0:
        raise ValueError(
            "Function `roundup` must be called only on positive numbers."
        )
    return int(a) + ((int(a) - a) != 0)


def log_notice(diag: Diagnostic) -> None:
    """Minimal function for `RAISE INFO`."""
    if diag.severity == "INFO":
        print(diag.message_primary)


def make_log_func_tqdm(
    pinfo: tqdm.std.tqdm,
) -> Callable[Diagnostic, None]:
    """Make a log function that update the tqdm description."""

    def log(diag: Diagnostic) -> None:
        """Show notice as a tqdm description."""

        if diag.severity == "INFO":
            pinfo.set_description(diag.message_primary)

    return log


class CallableDict(dict):
    """A dict that can be called to return an updated copy.

    a = {"group": 1, "name": "Aline"}
    b = a(name="Bernie")
    """

    def __call__(self, **kwargs):
        new = self.copy()
        new.update(kwargs)
        return new

    def copy(self):
        return self.__class__(super().copy())


def get_config_value(cur: Cursor, key: str) -> str:
    """Get a value from the configuration table."""
    stmt = SQL("SELECT {}._get_config(%s)").format(Identifier(SCHEMA))
    cur.execute(stmt, (key,))
    return cur.fetchone()[0]
