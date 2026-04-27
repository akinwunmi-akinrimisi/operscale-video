"""Shared pytest fixtures for Operscale agent tests.

Schema isolation: all Operscale tables live in the `operscale` schema (see
supabase/migrations/001_initial.sql + 005_grant_operscale_roles.sql).
Use `client.schema('operscale').table('<name>')` for every operation.
PostgREST exposure of the schema is configured at the Supabase project
level (PGRST_DB_SCHEMAS=public,sales_agent,operscale).
"""
import os
from typing import Any

import pytest


SUPABASE_SCHEMA = os.environ.get("SUPABASE_SCHEMA", "operscale")


@pytest.fixture
def supabase_service_client() -> Any:
    """Service-role Supabase client.

    Requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY in env (sourced from
    /docker/operscale-video-ads/.env.agent on the VPS, or a local .env for
    dev). The service role bypasses RLS and has GRANT ALL on operscale.*.

    Returns a client pre-bound to the operscale schema, so callers can
    write `client.table('customers').insert(...)` directly. To override
    the schema (e.g. for storage tests), use `client.schema('public')`.
    """
    try:
        from supabase import create_client
    except ImportError:
        pytest.skip("supabase-py not installed; install with `pip install supabase`")

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not (url and key):
        pytest.skip("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")

    client = create_client(url, key)
    return client.schema(SUPABASE_SCHEMA)
