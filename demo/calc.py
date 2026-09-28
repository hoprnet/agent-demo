"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""


def add(a: float, b: float) -> float:
    return a + b


def divide(a: float, b: float) -> float:
    """a / b; raises ZeroDivisionError for b == 0 like the operator does."""
    return a / b


def mean(values: list[float]) -> float:
    """Arithmetic mean; raises ValueError on an empty list."""
    if not values:
        raise ValueError("mean of an empty list")
    return sum(values) / len(values)


def clamp_int(x: int, lo: int, hi: int) -> int:
    """x limited to [lo, hi].

    >>> clamp_int(5, 0, 3)
    3
    """
    return max(lo, min(x, hi))
