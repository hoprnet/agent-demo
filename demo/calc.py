"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""

import math
from collections.abc import Sequence

SQRT2 = math.sqrt(2)


def add(a: float, b: float) -> float:
    """a + b.

    >>> add(2, 3)
    5
    """
    return a + b


def divide(a: float, b: float) -> float:
    """a / b; raises ZeroDivisionError for b == 0 like the operator does.

    >>> divide(6, 3)
    2.0
    >>> divide(1, 0)
    Traceback (most recent call last):
    ...
    ZeroDivisionError: division by zero
    """
    return a / b


def mean(values: Sequence[float]) -> float:
    """Arithmetic mean; raises ValueError on an empty sequence.

    >>> mean([1, 2, 3])
    2.0
    >>> mean([])
    Traceback (most recent call last):
    ...
    ValueError: mean of an empty sequence
    """
    if not values:
        raise ValueError("mean of an empty sequence")
    return sum(values) / len(values)


def variance(values: Sequence[float], *, sample: bool = True) -> float:
    """Sample variance (divides by n - 1) by default, raising ValueError for fewer than two values.
    With sample=False, population variance (divides by n), raising ValueError on an empty sequence.

    >>> variance([1, 3])
    2.0
    >>> variance([1, 3], sample=False)
    1.0
    >>> variance([5])
    Traceback (most recent call last):
    ...
    ValueError: variance needs at least two values
    >>> variance([5], sample=False)
    0.0
    >>> variance([], sample=False)
    Traceback (most recent call last):
    ...
    ValueError: variance of an empty sequence
    """
    divisor = len(values) - 1 if sample else len(values)
    if divisor < 1:
        raise ValueError("variance needs at least two values" if sample else "variance of an empty sequence")
    m = mean(values)
    return sum((v - m) ** 2 for v in values) / divisor


def stdev(values: Sequence[float], *, sample: bool = True) -> float:
    """Standard deviation, the square root of variance; same sample keyword and ValueError cases.

    >>> stdev([1, 3]) == SQRT2
    True
    >>> stdev([1, 3], sample=False)
    1.0
    >>> stdev([5])
    Traceback (most recent call last):
    ...
    ValueError: variance needs at least two values
    >>> stdev([5], sample=False)
    0.0
    """
    return math.sqrt(variance(values, sample=sample))


def zscore(x: float, values: Sequence[float], *, sample: bool = True) -> float:
    """(x - mean) / stdev; ValueError where stdev raises, ZeroDivisionError when all values are equal.

    >>> zscore(3, [1, 3]) == 1 / SQRT2
    True
    >>> zscore(3, [1, 3], sample=False)
    1.0
    >>> zscore(3, [3, 3, 3])
    Traceback (most recent call last):
    ...
    ZeroDivisionError: float division by zero
    """
    return (x - mean(values)) / stdev(values, sample=sample)
