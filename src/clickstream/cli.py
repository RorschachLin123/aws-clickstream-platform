import argparse
import json
from pathlib import Path
import sys
import time
from .events import load_dataset, write_dataset
from .publish import publish
from .reconcile import compare, query_rows


def session(profile: str | None, region: str):
    import boto3
    return boto3.Session(profile_name=profile, region_name=region)


def main() -> int:
    parser = argparse.ArgumentParser(description="Deterministic clickstream demonstration")
    parser.add_argument("--profile")
    parser.add_argument("--region", default="us-west-2")
    commands = parser.add_subparsers(dest="command", required=True)
    generate = commands.add_parser("generate")
    generate.add_argument("--out", type=Path, required=True)
    generate.add_argument("--run-id", required=True)
    generate.add_argument("--seed", type=int, default=42)
    generate.add_argument("--journeys", type=int, default=500)
    generate.add_argument("--base-time", default="2026-01-01T00:00:00Z")
    send = commands.add_parser("publish")
    send.add_argument("--dataset", type=Path, required=True)
    send.add_argument("--stream", required=True)
    send.add_argument("--receipt", type=Path, required=True)
    verify = commands.add_parser("reconcile")
    verify.add_argument("--dataset", type=Path, required=True)
    verify.add_argument("--workgroup", required=True)
    verify.add_argument("--database", default="clickstream_dev")
    verify.add_argument("--table", default="events")
    verify.add_argument("--out", type=Path, required=True)
    verify.add_argument("--wait-seconds", type=int, default=300)
    for operation in ("start", "stop", "purge-demo"):
        command = commands.add_parser(operation)
        command.add_argument("--application", default="clickstream-dev-pipeline")
        if operation == "purge-demo":
            command.add_argument("--database", default="clickstream_dev")
            command.add_argument("--bucket", required=True)
            command.add_argument("--confirm-bucket", required=True)
    args = parser.parse_args()
    if args.command == "generate":
        manifest = write_dataset(args.out, args.seed, args.journeys, args.run_id, args.base_time)
        print(json.dumps({k: v for k, v in manifest.items() if k != "expected_rows"}, indent=2))
        return 0
    from botocore.config import Config
    aws = session(args.profile, args.region)
    if args.command in ("start", "stop", "purge-demo"):
        from .runtime import start, stop, purge_demo, verify_deadline
        if args.command == "purge-demo":
            purge_demo(aws, args.application, args.database, args.bucket, args.confirm_bucket)
        else:
            if args.command == "start":
                verify_deadline(aws.client("scheduler"), args.application)
            operation = start if args.command == "start" else stop
            operation(aws.client("kinesisanalyticsv2"), args.application)
        return 0
    manifest, events = load_dataset(args.dataset)
    if args.command == "publish":
        if args.receipt.exists():
            raise ValueError("receipt already exists; this append-only run must not be republished")
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        # Create before sending: an interrupted run must be investigated instead of replayed.
        with args.receipt.open("x") as receipt:
            json.dump(dict(status="IN_PROGRESS", run_id=manifest["run_id"], sha256=manifest["sha256"]), receipt)
        account = aws.client("sts").get_caller_identity()["Account"]
        credentials = aws.client("sts").assume_role(RoleArn=f"arn:aws:iam::{account}:role/clickstream-dev-producer", RoleSessionName="clickstream-producer", DurationSeconds=900)["Credentials"]
        import boto3
        producer = boto3.Session(aws_access_key_id=credentials["AccessKeyId"], aws_secret_access_key=credentials["SecretAccessKey"], aws_session_token=credentials["SessionToken"], region_name=args.region)
        client = producer.client("kinesis", config=Config(retries={"total_max_attempts": 1, "mode": "standard"}, connect_timeout=5, read_timeout=20))
        count = publish(client, args.stream, events)
        args.receipt.write_text(json.dumps(dict(status="ACKNOWLEDGED", run_id=manifest["run_id"], sha256=manifest["sha256"], acknowledged_records=count), indent=2) + "\n")
        print(f"Acknowledged {count} records; reconcile Athena before claiming delivery")
        return 0
    if not 1 <= args.wait_seconds <= 900:
        raise ValueError("wait-seconds must be between 1 and 900")
    client = aws.client("athena", config=Config(retries={"total_max_attempts": 3, "mode": "standard"}, connect_timeout=5, read_timeout=20))
    deadline = time.monotonic() + args.wait_seconds
    queries = []
    while True:
        actual, evidence = query_rows(client, args.workgroup, args.database, args.table, manifest["run_id"], timeout=min(60, max(1, int(deadline-time.monotonic()))))
        queries.append(evidence)
        result = compare(events, actual)
        if result["matches"] or time.monotonic() >= deadline:
            break
        if result["unexpected_rows"] or result["duplicate_business_keys"]:
            break
        time.sleep(min(10, max(0, deadline-time.monotonic())))
    result.update(run_id=manifest["run_id"], manifest_sha256=manifest["sha256"], queries=queries, actual_rows=actual)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "actual_rows"}, indent=2))
    return 0 if result["matches"] else 1


if __name__ == "__main__":
    sys.exit(main())
