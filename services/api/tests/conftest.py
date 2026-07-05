"""Pytest configuration for API tests."""

import pytest


@pytest.fixture
def anyio_backend():
    return "asyncio"
