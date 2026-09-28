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


def test_harmonic_mean():
    assert calc.harmonic_mean([1, 1]) == 1
    assert calc.harmonic_mean([1, 2, 4]) == pytest.approx(12 / 7)
    for bad in ([], [1, 0], [1, -2]):
        with pytest.raises(ValueError):
            calc.harmonic_mean(bad)
