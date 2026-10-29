from pathlib import Path

import pytest

FIXTURES = Path(__file__).resolve().parents[2] / "compat" / "fixtures"


def fixture_paths():
    return sorted(FIXTURES.glob("*.dta"))


@pytest.fixture(params=fixture_paths(), ids=lambda p: p.stem)
def fixture(request):
    return request.param
