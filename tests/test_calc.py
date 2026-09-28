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


def test_variance():
    assert calc.variance([2, 4, 4, 4, 5, 5, 7, 9]) == pytest.approx(32 / 7)
    with pytest.raises(ValueError):
        calc.variance([])
    with pytest.raises(ValueError):
        calc.variance([5])


def test_variance_accepts_tuple():
    assert calc.variance((2, 4, 4, 4, 5, 5, 7, 9)) == pytest.approx(32 / 7)
    with pytest.raises(ValueError):
        calc.variance((5,))
