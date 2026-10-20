import unittest
from unittest.mock import Mock
from clickstream.publish import publish
from clickstream.reconcile import query_rows


class PublishTest(unittest.TestCase):
    def test_only_explicit_failures_retried(self):
        client = Mock()
        client.put_records.side_effect = [dict(Records=[dict(SequenceNumber='1'), dict(ErrorCode='ProvisionedThroughputExceededException')]), dict(Records=[dict(SequenceNumber='2')])]
        self.assertEqual(publish(client, 'stream', [dict(impression_id='a'), dict(impression_id='b')], sleep=lambda _: None), 2)
        self.assertEqual(len(client.put_records.call_args.kwargs['Records']), 1)
        self.assertEqual(client.put_records.call_args.kwargs['Records'][0]['PartitionKey'], 'b')

    def test_ambiguous_transport_error_not_retried(self):
        client = Mock()
        client.put_records.side_effect = TimeoutError('unknown acknowledgement')
        with self.assertRaises(TimeoutError):
            publish(client, 'stream', [dict(impression_id='a')])
        self.assertEqual(client.put_records.call_count, 1)

    def test_persistent_failures_abort(self):
        client = Mock()
        client.put_records.return_value = dict(Records=[dict(ErrorCode='InternalFailure')])
        with self.assertRaises(RuntimeError):
            publish(client, 'stream', [dict(impression_id='a')], sleep=lambda _: None, attempts=2)

    def test_athena_pagination_and_money_type(self):
        client = Mock()
        client.start_query_execution.return_value = dict(QueryExecutionId='query-1')
        client.get_query_execution.return_value = dict(QueryExecution=dict(Status=dict(State='SUCCEEDED'), Statistics=dict(DataScannedInBytes=17)))
        header = dict(Data=[dict(VarCharValue='event_id')])
        def row(event_id):
            return dict(Data=[dict(VarCharValue=v) for v in [event_id, 'run', 'impression', 'user', 'app', 'campaign', 'payment', '2026-01-01T00:00:00.000Z', '199']])
        client.get_paginator.return_value.paginate.return_value = [dict(ResultSet=dict(Rows=[header, row('a')])), dict(ResultSet=dict(Rows=[row('b')]))]
        rows, evidence = query_rows(client, 'wg', 'clickstream_dev', 'events', 'run')
        self.assertEqual([r['event_id'] for r in rows], ['a', 'b'])
        self.assertEqual(rows[0]['amount_cents'], 199)
        self.assertEqual(evidence['scanned_bytes'], 17)
        with self.assertRaises(ValueError):
            query_rows(client, 'wg', 'bad;sql', 'events', 'run')


if __name__ == '__main__':
    unittest.main()
