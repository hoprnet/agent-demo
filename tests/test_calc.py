import pytest

from demo import calc


def test_add():
    assert calc.add(2, 3) == 5
    assert calc.add(-1, 1) == 0


def test_divide():
    assert calc.divide(6, 3) == 2
    with pytest.raises(ZeroDivisionError):
        calc.divide(1, 0)


def test_mean():
    assert calc.mean([1, 2, 3]) == 2
    with pytest.raises(ValueError):
        calc.mean([])


def test_clamp01():
    assert calc.clamp01(0.5) == 0.5
    assert calc.clamp01(0.0) == 0.0
    assert calc.clamp01(1.0) == 1.0
    assert calc.clamp01(-2) == 0.0
    assert calc.clamp01(3) == 1.0
