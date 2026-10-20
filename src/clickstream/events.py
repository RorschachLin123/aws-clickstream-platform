"""Pure, deterministic baseline generator; no network or wall-clock dependency."""
from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import random
import re
from uuid import UUID, uuid5

FIELDS = ("event_id", "run_id", "impression_id", "user_id", "app_id", "campaign_id", "event_type", "event_time", "amount_cents")
NAMESPACE = UUID("97f57c18-d5a6-5f83-9034-8ac66c68d305")


def validate_run_id(run_id: str) -> str:
    if not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", run_id):
        raise ValueError("run_id must be 1-64 letters, numbers, underscores or hyphens")
    return run_id


def generate(seed: int, journeys: int, run_id: str, base_time: str) -> list[dict]:
    validate_run_id(run_id)
    if not 1 <= journeys <= 10000:
        raise ValueError("journeys must be between 1 and 10000")
    base = datetime.fromisoformat(base_time.replace("Z", "+00:00"))
    if base.tzinfo is None or base.utcoffset() != timedelta(0):
        raise ValueError("base_time must contain a UTC timezone")
    rng = random.Random(seed)
    events = []
    for i in range(journeys):
        impression = str(uuid5(NAMESPACE, f"{run_id}/{seed}/{i}"))
        shared = dict(run_id=run_id, impression_id=impression, user_id=f"user-{rng.randrange(1000):04d}", app_id=f"app-{rng.randrange(5)}", campaign_id=f"campaign-{rng.randrange(8)}")
        types = ["impression"]
        for name, probability in [("click", .6), ("install", .5), ("activation", .8), ("payment", .25)]:
            if rng.random() >= probability:
                break
            types.append(name)
        for ordinal, kind in enumerate(types):
            moment = base + timedelta(seconds=i * 10 + ordinal)
            events.append(dict(shared, event_id=str(uuid5(NAMESPACE, f"{impression}/{kind}")), event_type=kind, event_time=moment.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"), amount_cents=rng.choice([199, 499, 999]) if kind == "payment" else 0))
    return events


def encode(events: list[dict]) -> bytes:
    return b"".join((json.dumps(e, sort_keys=True, separators=(",", ":")) + "\n").encode() for e in events)


def write_dataset(directory: Path, seed: int, journeys: int, run_id: str, base_time: str) -> dict:
    if directory.exists() and any(directory.iterdir()):
        raise ValueError("output directory must be empty; preserve previous manifests")
    events = generate(seed, journeys, run_id, base_time)
    data = encode(events)
    manifest = dict(schema_version=1, run_id=run_id, seed=seed, journeys=journeys, base_time=base_time, event_count=len(events), sha256=hashlib.sha256(data).hexdigest(), counts_by_type=dict(sorted(Counter(e["event_type"] for e in events).items())), expected_rows=events)
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "events.jsonl").write_bytes(data)
    (directory / "manifest.json").write_text(json.dumps(manifest, sort_keys=True, indent=2) + "\n")
    return manifest


def load_dataset(directory: Path) -> tuple[dict, list[dict]]:
    manifest = json.loads((directory / "manifest.json").read_text())
    data = (directory / "events.jsonl").read_bytes()
    events = [json.loads(line) for line in data.splitlines()]
    if hashlib.sha256(data).hexdigest() != manifest["sha256"] or events != manifest["expected_rows"] or len(events) != manifest["event_count"]:
        raise ValueError("dataset does not match manifest")
    if len({e["event_id"] for e in events}) != len(events):
        raise ValueError("manifest has duplicate event IDs")
    validate_run_id(manifest["run_id"])
    return manifest, events
