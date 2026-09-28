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


def variance(values: Sequence[float]) -> float:
    """Sample variance (divides by n - 1). Raises ValueError for fewer than two values."""
    if len(values) < 2:
        raise ValueError("variance needs at least two values")
    m = mean(values)
    return sum((v - m) ** 2 for v in values) / (len(values) - 1)


def stdev(values: Sequence[float]) -> float:
    """Sample standard deviation, the square root of variance. Raises ValueError for fewer than two values."""
    return math.sqrt(variance(values))
