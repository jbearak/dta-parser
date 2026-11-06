from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "compat" / "fixtures"
PARQUET = ROOT / "compat" / "parquet"


def fixture_paths():
    return sorted(FIXTURES.glob("*.dta"))


@pytest.fixture(params=fixture_paths(), ids=lambda p: p.stem)
def dta(request):
    return request.param
