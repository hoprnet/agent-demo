"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""

import math


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


def geometric_mean(values: list[float]) -> float:
    """n-th root of the product of n positive values; raises ValueError on an empty list or a value <= 0.

    >>> geometric_mean([1, 3, 9])
    3.0
    """
    if not values:
        raise ValueError("geometric mean of an empty list")
    if any(v <= 0 for v in values):
        raise ValueError("geometric mean needs positive values")
    return math.prod(values) ** (1 / len(values))
