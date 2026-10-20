import hashlib
from pathlib import Path
import tempfile
import unittest
from clickstream.events import encode, generate, load_dataset, write_dataset
from clickstream.reconcile import compare


class EventsTest(unittest.TestCase):
    def dataset(self):
        return generate(42, 20, "golden-v1", "2026-01-01T00:00:00Z")

    def test_reproducible_and_unique(self):
        events = self.dataset()
        self.assertEqual(encode(events), encode(self.dataset()))
        self.assertEqual(len(events), len({e['event_id'] for e in events}))
        self.assertNotEqual(encode(events), encode(generate(43, 20, 'golden-v1', '2026-01-01T00:00:00Z')))
        # A fixed digest protects reproducibility across generator edits.
        self.assertEqual(hashlib.sha256(encode(events)).hexdigest(), 'f8536afca4c38b81659cf1e77c070b6a3bf3040c9dba70211484c49ff4a3984d')

    def test_funnel_parents_and_money(self):
        seen = {}
        kinds = ['impression', 'click', 'install', 'activation', 'payment']
        for event in self.dataset():
            prior = seen.setdefault(event['impression_id'], [])
            self.assertEqual(event['event_type'], kinds[len(prior)])
            prior.append(event['event_type'])
            self.assertEqual(event['amount_cents'] > 0, event['event_type'] == 'payment')

    def test_invalid_inputs(self):
        for journeys, run_id, base in [(0, 'ok', '2026-01-01T00:00:00Z'), (10001, 'ok', '2026-01-01T00:00:00Z'), (1, "sql'", '2026-01-01T00:00:00Z'), (1, 'ok', '2026-01-01T00:00:00')]:
            with self.assertRaises(ValueError):
                generate(42, journeys, run_id, base)

    def test_manifest_tampering_and_overwrite(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'data'
            write_dataset(path, 42, 20, 'golden-v1', '2026-01-01T00:00:00Z')
            self.assertEqual(load_dataset(path)[1], self.dataset())
            with self.assertRaises(ValueError):
                write_dataset(path, 42, 20, 'golden-v1', '2026-01-01T00:00:00Z')
            (path / 'events.jsonl').write_bytes((path / 'events.jsonl').read_bytes() + b'\n')
            with self.assertRaises(ValueError):
                load_dataset(path)

    def test_reconciliation_detects_equal_count_corruption(self):
        expected = self.dataset()
        self.assertTrue(compare(expected, list(reversed(expected)))['matches'])
        for changed in [expected[:-1], expected + expected[:1], [dict(expected[0], amount_cents=12)] + expected[1:], expected[1:] + [expected[1]]]:
            self.assertFalse(compare(expected, changed)['matches'])


if __name__ == '__main__':
    unittest.main()
