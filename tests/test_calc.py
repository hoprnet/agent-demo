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


def test_variance_population():
    assert calc.variance([2, 4, 4, 4, 5, 5, 7, 9], sample=False) == pytest.approx(32 / 8)
    assert calc.variance((1, 3), sample=False) == pytest.approx(1)
    assert calc.variance([5], sample=False) == 0.0
    with pytest.raises(ValueError):
        calc.variance([], sample=False)
    assert calc.variance([2, 4, 4, 4, 5, 5, 7, 9], sample=True) == pytest.approx(32 / 7)


def test_stdev():
    assert calc.stdev([2, 4, 4, 4, 5, 5, 7, 9]) == pytest.approx((32 / 7) ** 0.5)
    assert calc.stdev((1, 3)) == pytest.approx(2**0.5)
    with pytest.raises(ValueError):
        calc.stdev([])
    with pytest.raises(ValueError):
        calc.stdev([5])


def test_stdev_population():
    assert calc.stdev([2, 4, 4, 4, 5, 5, 7, 9], sample=False) == pytest.approx(2)
    assert calc.stdev((1, 3), sample=False) == pytest.approx(1)
    assert calc.stdev([5], sample=False) == 0.0
    with pytest.raises(ValueError):
        calc.stdev([], sample=False)
    assert calc.stdev([2, 4, 4, 4, 5, 5, 7, 9], sample=True) == pytest.approx((32 / 7) ** 0.5)


def test_stdev_zero_spread():
    assert calc.stdev([3, 3, 3]) == 0.0
    assert calc.stdev([3, 3, 3], sample=False) == 0.0
    assert calc.stdev([5], sample=False) == 0.0
