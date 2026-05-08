"""Fixtures for astro tests."""

import importlib.machinery
import importlib.util
import sys
import warnings
from pathlib import Path

import pytest

# Silence kerykeion v5 deprecation warnings (legacy AstrologicalSubject /
# NatalAspects / SynastryAspects). Migration to the v5 Factory pattern is
# a separate task; bin/astro installs the same filter at module load.
# kerykeion uses stacklevel=2 so warnings appear to originate from caller —
# filter by message text instead of module regex.
warnings.filterwarnings(
    'ignore', category=DeprecationWarning,
    message=r".*(deprecated in Kerykeion|"
            r"'AstrologicalSubject' is deprecated|"
            r"'NatalAspects' is deprecated|"
            r"'SynastryAspects' is deprecated|"
            r"'true_node'|'true_south_node'|'mean_lilith').*",
)


@pytest.fixture(scope="session")
def astro_module():
    """Import the astro script as a module."""
    astro_path = Path.home() / "dotfiles" / "bin" / "astro"
    # File has no .py extension, so we must specify the loader explicitly
    loader = importlib.machinery.SourceFileLoader("astro", str(astro_path))
    spec = importlib.util.spec_from_file_location("astro", astro_path, loader=loader)
    mod = importlib.util.module_from_spec(spec)
    sys.modules["astro"] = mod
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture(scope="session")
def transit_calc(astro_module, tmp_path_factory):
    """Create a TransitCalculator with a temp storage dir."""
    tmp = tmp_path_factory.mktemp("astro_storage")
    storage = astro_module.AstroStorage(base_path=tmp)
    return astro_module.TransitCalculator(storage)


@pytest.fixture(scope="session")
def birth_data(astro_module):
    """Anthony's birth data for integration tests."""
    return astro_module.BirthData(
        full_name="anthony",
        year=1993, month=10, day=20,
        hour=16, minute=14,
        city="Provo", nation="US",
        lat=40.2338, lng=-111.6585,
        tz_str="America/Denver",
    )


@pytest.fixture(scope="session")
def natal_subject(transit_calc, birth_data):
    """Kerykeion natal subject for Anthony."""
    return transit_calc._make_subject(
        birth_data.full_name,
        birth_data.year, birth_data.month, birth_data.day,
        birth_data.hour, birth_data.minute,
        birth_data,
    )


@pytest.fixture(scope="session")
def natal_cusps(transit_calc, natal_subject):
    """Natal house cusps dict."""
    return transit_calc._calculate_natal_houses(natal_subject)
