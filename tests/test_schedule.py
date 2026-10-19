import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class ScheduleTests(unittest.TestCase):
    def test_expected_slots_for_intervals(self):
        for interval, count in [(60,24),(30,48),(20,72),(15,96),(10,144),(5,288)]:
            with self.subTest(interval=interval), tempfile.TemporaryDirectory() as td:
                env = os.environ.copy()
                env.update(DATA_DIR=td, CAPTURE_INTERVAL_MINUTES=str(interval))
                subprocess.run(['python3', str(ROOT / 'tapo-schedule'), 'init', str(interval)], env=env, check=True, capture_output=True)
                p = subprocess.run(['python3',str(ROOT/'tapo-schedule'),'expected','2026-10-18'],env=env,text=True,capture_output=True,check=True)
                slots=json.loads(p.stdout)
                self.assertEqual(len(slots),count)
                self.assertEqual(slots[0],'00:00')
                self.assertEqual(len(slots),len(set(slots)))

if __name__ == '__main__': unittest.main()
