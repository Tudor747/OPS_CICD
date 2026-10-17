import importlib.util
import os
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location('monitor', Path(__file__).parents[1] / 'ops' / 'monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class MonitorTests(unittest.TestCase):
    def run_check(self, *, disk=20, memory=80, backup='1000', http_error=False, service=0):
        response = MagicMock()
        response.__enter__.return_value.status = 200
        response.__enter__.return_value.read.return_value = b'{"status":"ok"}'

        def read(path):
            if path.name == 'meminfo':
                return f'MemTotal: 100 kB\nMemAvailable: {memory} kB\n'
            if backup is None:
                raise FileNotFoundError()
            return backup

        with patch.dict(os.environ, {'PUBLIC_URL': 'https://example.test/health',
                                    'DISK_THRESHOLD': '85', 'MEMORY_THRESHOLD': '90',
                                    'BACKUP_MAX_AGE_HOURS': '30'}, clear=True), \
             patch.object(monitor.subprocess, 'run', return_value=SimpleNamespace(returncode=service)), \
             patch.object(monitor.shutil, 'disk_usage', return_value=SimpleNamespace(used=disk, total=100)), \
             patch.object(Path, 'exists', return_value=True), \
             patch.object(Path, 'read_text', read), \
             patch.object(monitor.time, 'time', return_value=1100), \
             patch.object(monitor.urllib.request, 'urlopen', side_effect=OSError('offline') if http_error else None, return_value=response):
            return monitor.check()

    def test_healthy(self):
        self.assertEqual(self.run_check(), [])

    def test_failed_services_and_http(self):
        failures = self.run_check(service=1, http_error=True)
        self.assertEqual(len(failures), 4)

    def test_resource_pressure(self):
        failures = self.run_check(disk=95, memory=5)
        self.assertTrue(any('Disk usage' in item for item in failures))
        self.assertTrue(any('Memory usage' in item for item in failures))

    def test_backup_missing_stale_or_corrupt(self):
        for value in (None, '-200000', 'invalid', '9999999'):
            with self.subTest(value=value):
                self.assertEqual(len(self.run_check(backup=value)), 1)


if __name__ == '__main__':
    unittest.main()
