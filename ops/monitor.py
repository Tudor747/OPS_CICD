#!/usr/bin/env python3
"""Host checks; run with the environment loaded by monitor.sh."""
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path


def check():
    failures = []
    for unit in ('docker', 'apache2'):
        result = subprocess.run(['systemctl', 'is-active', '--quiet', unit], check=False)
        if result.returncode:
            failures.append(f'{unit} is not active')
    for path in ('/', '/var/lib/docker', '/var/backups/hosting'):
        if Path(path).exists():
            usage = shutil.disk_usage(path)
            if usage.used / usage.total * 100 >= int(os.getenv('DISK_THRESHOLD', '85')):
                failures.append(f'Disk usage is high on {path}')
    memory = dict(line.split(':', 1) for line in Path('/proc/meminfo').read_text().splitlines())
    used = 100 * (1 - int(memory['MemAvailable'].split()[0]) / int(memory['MemTotal'].split()[0]))
    if used >= int(os.getenv('MEMORY_THRESHOLD', '90')):
        failures.append(f'Memory usage is high ({used:.0f}%)')
    for url in ('http://127.0.0.1:3001/health', os.environ['PUBLIC_URL']):
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                if response.status != 200 or json.load(response) != {'status': 'ok'}:
                    failures.append(f'Unexpected health response from {url}')
        except Exception as error:
            failures.append(f'Health check failed for {url}: {error}')
    stamp = Path('/var/lib/hosting/last-backup')
    try:
        age = time.time() - int(stamp.read_text().strip())
        if age < 0 or age > int(os.getenv('BACKUP_MAX_AGE_HOURS', '30')) * 3600:
            failures.append('Backup is overdue or timestamp is invalid')
    except (OSError, ValueError):
        failures.append('No successful backup recorded')
    return failures


if __name__ == '__main__':
    failures = check()
    message = '\n'.join(failures) if failures else 'Hosting checks passed'
    print(message, flush=True)
    webhook = os.getenv('ALERT_WEBHOOK')
    if failures and webhook:
        if not webhook.startswith('https://'):
            raise ValueError('ALERT_WEBHOOK must use HTTPS')
        request = urllib.request.Request(webhook, data=json.dumps({'text': message}).encode(),
                                         headers={'Content-Type': 'application/json'}, method='POST')
        with urllib.request.urlopen(request, timeout=15) as response:
            response.read()
    sys.exit(1 if failures else 0)
