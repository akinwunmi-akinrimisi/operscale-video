#!/usr/bin/env python3
"""seed_test_order.py — Insert a synthetic test order into Supabase.

Loads a fixture from apps/agent/tests/fixtures/scripts/<niche>.json,
inserts customers + briefs + orders + videos + scenes rows in the
`operscale` schema (see supabase/migrations/001_initial.sql for the
schema isolation rationale), prints the resulting UUIDs.

Usage:
  python apps/agent/tests/seed_test_order.py --niche real-estate --tier pilot
  python apps/agent/tests/seed_test_order.py --all-niches  (Day 11)

Env (sourced from /docker/operscale-video-ads/.env.agent on the VPS):
  SUPABASE_URL                — e.g. https://supabase.operscale.cloud
  SUPABASE_SERVICE_ROLE_KEY   — JWT with role=service_role
  SUPABASE_SCHEMA             — defaults to 'operscale'
"""
import argparse
import json
import os
import sys
import uuid
from pathlib import Path


SUPABASE_SCHEMA = os.environ.get("SUPABASE_SCHEMA", "operscale")


def load_fixture(niche: str) -> dict:
    repo_root = Path(__file__).resolve().parent.parent.parent.parent
    fixture = (
        repo_root
        / "apps"
        / "agent"
        / "tests"
        / "fixtures"
        / "scripts"
        / f"{niche}.json"
    )
    if not fixture.exists():
        sys.exit(f"❌ Fixture not found: {fixture}")
    return json.loads(fixture.read_text())


def seed_one(client, fixture: dict) -> tuple[str, str]:
    """Insert customers + briefs + orders + videos + scenes; return (order_id, video_id).

    `client` must be schema-bound to operscale (use client.schema('operscale')
    when constructing the bound client).
    """
    test_email = f"test-{uuid.uuid4().hex[:8]}@operscale-foundation.test"
    cust = client.table("customers").insert({
        "email": test_email,
        "business_name": f"Foundation Test ({fixture['niche']})",
        "whatsapp_phone": "+2348000000000",
        "source": "foundation-test",
    }).execute()
    customer_id = cust.data[0]["id"]

    brief = client.table("briefs").insert({
        "customer_id": customer_id,
        "niche": fixture["niche"],
        "business_name": f"Foundation Test {fixture['niche']}",
        "product_or_service": f"Foundation test for {fixture['niche']} render",
        "call_to_action": "WhatsApp us",
    }).execute()
    brief_id = brief.data[0]["id"]

    order = client.table("orders").insert({
        "customer_id": customer_id,
        "brief_id": brief_id,
        "tier": fixture["tier"],
        "amount_paid_kobo": 7500000 if fixture["tier"] == "pilot" else 17500000,
        "niche": fixture["niche"],
        "production_register": fixture["production_register"],
        "pipeline_stage": "production_documentary",
    }).execute()
    order_id = order.data[0]["id"]

    video = client.table("videos").insert({
        "order_id": order_id,
        "video_number": 1,
        "script_json": fixture,
        "scene_count": len(fixture["scenes"]),
        "duration_seconds": fixture["duration_target_sec"],
        "revisions_max": 1 if fixture["tier"] == "pilot" else 2,
    }).execute()
    video_id = video.data[0]["id"]

    scenes_payload = []
    for s in fixture["scenes"]:
        scenes_payload.append({
            "video_id": video_id,
            "order_id": order_id,
            "scene_number": s["scene_number"],
            "scene_id": s["scene_id"],
            "narration_text": s["narration_text"],
            "image_prompt": s["image_prompt"],
            "composition_prefix": s["composition_prefix"],
            "color_mood": s["color_mood"],
            "zoom_direction": s["zoom_direction"],
            "transition_to_next": s["transition_to_next"],
            "caption_highlight_word": s["caption_highlight_word"],
        })
    client.table("scenes").insert(scenes_payload).execute()

    return order_id, video_id


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--niche", help="Single niche fixture name")
    ap.add_argument(
        "--tier",
        default="pilot",
        choices=["pilot", "standard", "creative_pod"],
    )
    ap.add_argument(
        "--all-niches",
        action="store_true",
        help="Seed all 5 niches",
    )
    args = ap.parse_args()

    if not (args.niche or args.all_niches):
        ap.error("Pass --niche <name> or --all-niches")

    try:
        from supabase import create_client
    except ImportError:
        sys.exit("supabase-py not installed; pip install supabase")

    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not (url and key):
        sys.exit("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
    client = create_client(url, key).schema(SUPABASE_SCHEMA)

    niches = (
        ["real-estate", "education", "fashion-ecom", "fintech", "health"]
        if args.all_niches
        else [args.niche]
    )
    for n in niches:
        fixture = load_fixture(n)
        if not args.all_niches and args.tier != fixture["tier"]:
            fixture["tier"] = args.tier
        order_id, video_id = seed_one(client, fixture)
        print(f"{n}: order_id={order_id}  video_id={video_id}")


if __name__ == "__main__":
    main()
