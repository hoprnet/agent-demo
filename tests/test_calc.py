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


def test_percent():
    assert calc.percent(1, 2) == 50
    assert calc.percent(3, 4) == 75
    with pytest.raises(ZeroDivisionError):
        calc.percent(1, 0)
