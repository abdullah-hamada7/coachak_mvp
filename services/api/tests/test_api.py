"""API integration tests."""

import pytest
from httpx import ASGITransport, AsyncClient

from app.main import app


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.mark.asyncio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"


@pytest.mark.asyncio
async def test_register_and_login(client):
    resp = await client.post("/auth/register", json={
        "email": "test@coachak.dev",
        "password": "testpass123",
        "display_name": "Test User",
    })
    assert resp.status_code == 200
    assert "access_token" in resp.json()

    resp = await client.post("/auth/login", json={
        "email": "test@coachak.dev",
        "password": "testpass123",
    })
    assert resp.status_code == 200
