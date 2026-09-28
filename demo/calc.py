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


def harmonic_mean(values: list[float]) -> float:
    """Harmonic mean: n divided by the sum of reciprocals."""
    return len(values) / sum(1 / v for v in values)
