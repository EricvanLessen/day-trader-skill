import unittest
from datetime import datetime
from zoneinfo import ZoneInfo

from ops.web.app import brief_payload, scheduled_mode, top_symbols


class MonitorTest(unittest.TestCase):
    def test_schedule_hourly_et_only(self):
        et = ZoneInfo("America/New_York")
        self.assertEqual(scheduled_mode(datetime(2026, 11, 6, 9, 0, tzinfo=et)), "daily")
        self.assertEqual(scheduled_mode(datetime(2026, 11, 6, 10, 0, tzinfo=et)), "orb")
        self.assertEqual(scheduled_mode(datetime(2026, 11, 6, 15, 0, tzinfo=et)), "orb")
        self.assertIsNone(scheduled_mode(datetime(2026, 11, 6, 10, 5, tzinfo=et)))
        self.assertIsNone(scheduled_mode(datetime(2026, 11, 6, 16, 0, tzinfo=et)))
        self.assertIsNone(scheduled_mode(datetime(2026, 11, 7, 10, 0, tzinfo=et)))

    def test_brief_preserves_partial_counts(self):
        scan = {"partial": True, "failed": 32, "hits": [{"symbol": "AAPL"}, {"symbol": "TSLA"}]}
        summary = brief_payload(scan, max_hits=1)
        self.assertEqual(summary["hits"], [{"symbol": "AAPL"}])
        self.assertEqual(summary["total_hits"], 2)
        self.assertEqual(summary["failed"], 32)
        self.assertTrue(summary["partial"])

    def test_only_valid_tickers(self):
        self.assertEqual(top_symbols({"hits": [{"symbol": "AAPL"}, {"symbol": "AAPL"}, {"symbol": "X;rm"}, {"symbol": "BRK.B"}]}), ["AAPL", "BRK.B"])


if __name__ == "__main__":
    unittest.main()
