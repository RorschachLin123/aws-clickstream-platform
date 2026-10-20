"""Compare a bounded demo run against every expected value, not just aggregate counts."""
from collections import Counter
import time
import re
from .events import FIELDS, validate_run_id


def compare(expected: list[dict], actual: list[dict]) -> dict:
    def row_key(row):
        return tuple(row.get(k) for k in FIELDS)
    wanted, found = Counter(map(row_key, expected)), Counter(map(row_key, actual))
    ids = Counter(r.get("event_id") for r in actual)
    return dict(matches=wanted == found, expected_count=len(expected), actual_count=len(actual), distinct_business_keys=len(ids), duplicate_business_keys=sum(n - 1 for n in ids.values()), missing_rows=sum((wanted - found).values()), unexpected_rows=sum((found - wanted).values()))


def query_rows(client, workgroup: str, database: str, table: str, run_id: str, timeout: int = 90, *, sleep=time.sleep) -> tuple[list[dict], dict]:
    for identifier in (database, table):
        if not re.fullmatch(r"[a-z][a-z0-9_]{0,62}", identifier):
            raise ValueError("invalid SQL identifier")
    validate_run_id(run_id)
    query = f'SELECT {", ".join(FIELDS)} FROM "{database}"."{table}" WHERE run_id = \'{run_id}\''
    query_id = client.start_query_execution(QueryString=query, WorkGroup=workgroup, QueryExecutionContext={"Database": database, "Catalog": "AwsDataCatalog"})["QueryExecutionId"]
    deadline = time.monotonic() + timeout
    while True:
        execution = client.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]
        status = execution["Status"]["State"]
        if status == "SUCCEEDED":
            break
        if status in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Athena {query_id}: {execution['Status'].get('StateChangeReason', status)}")
        if time.monotonic() >= deadline:
            client.stop_query_execution(QueryExecutionId=query_id)
            raise TimeoutError(f"Athena query {query_id} timed out and was cancelled")
        sleep(2)
    rows = []
    header = True
    for page in client.get_paginator("get_query_results").paginate(QueryExecutionId=query_id):
        for row in page["ResultSet"]["Rows"]:
            if header:
                header = False
                continue
            values = [c.get("VarCharValue") for c in row["Data"]]
            mapped = dict(zip(FIELDS, values))
            mapped["amount_cents"] = int(mapped["amount_cents"]) if mapped.get("amount_cents") is not None else None
            rows.append(mapped)
    return rows, dict(query_id=query_id, scanned_bytes=execution.get("Statistics", {}).get("DataScannedInBytes", 0), sql=query)
