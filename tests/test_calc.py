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


def test_clamp():
    assert calc.clamp(5, 0, 10) == 5
    assert calc.clamp(-3, 0, 10) == 0
    assert calc.clamp(42, 0, 10) == 10
    assert calc.clamp(7, 3, 3) == 3
    with pytest.raises(ValueError):
        calc.clamp(1, 2, 1)
