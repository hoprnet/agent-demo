"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""


def add(a: float, b: float) -> float:
    return a + b


def divide(a: float, b: float) -> float:
    """a / b; raises ZeroDivisionError for b == 0 like the operator does."""
    return a / b


def mean(values: list[float]) -> float:
    """Arithmetic mean; 0.0 for an empty list, so callers aggregating optional data need no special case."""
    if not values:
        return 0.0
    return sum(values) / len(values)
