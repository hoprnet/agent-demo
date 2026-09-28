"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""

import math
from collections.abc import Sequence


def add(a: float, b: float) -> float:
    return a + b


def divide(a: float, b: float) -> float:
    """a / b; raises ZeroDivisionError for b == 0 like the operator does."""
    return a / b


def mean(values: Sequence[float]) -> float:
    """Arithmetic mean; raises ValueError on an empty sequence."""
    if not values:
        raise ValueError("mean of an empty list")
    return sum(values) / len(values)


def variance(values: Sequence[float], *, sample: bool = True) -> float:
    """Sample variance (divides by n - 1) by default, raising ValueError for fewer than two values.
    With sample=False, population variance (divides by n), raising ValueError on an empty sequence."""
    ddof = 1 if sample else 0
    if len(values) < ddof + 1:
        raise ValueError("variance needs at least two values" if sample else "variance of an empty sequence")
    m = mean(values)
    return sum((v - m) ** 2 for v in values) / (len(values) - ddof)


def stdev(values: Sequence[float]) -> float:
    """Sample standard deviation, the square root of variance. Raises ValueError for fewer than two values."""
    return math.sqrt(variance(values))
