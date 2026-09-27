"""A small module the proof-of-concept pull requests change. Keep it small: the point is the review loop, not the code."""

import statistics


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


def median(values: list[float]) -> float:
    """Middle value of the list; for an even count, the mean of the two middle values. Raises ValueError (statistics.StatisticsError) on an empty list."""
    return statistics.median(values)
