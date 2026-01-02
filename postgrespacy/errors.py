from .util import get_result_row_types


class InvalidRowType(ValueError):
    def __init__(self, cursor=None, required=None):
        if cursor:
            received = get_result_row_types(cursor)
        self.required = required
        self.received = received
        if required and received:
            self.message = (
                f"Required: {str(required)}. Got: {str(received)}"
            )
        else:
            self.message = (
                "Wrong types in rows returned by `Cursor.execute(...)`."
            )
        super().__init__(self.message)
