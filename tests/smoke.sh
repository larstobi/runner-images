#!/usr/bin/env bash
set -euo pipefail

test "$(id -u)" = 1000
test -w /work
test ! -w /usr/local/bin
node --version
git --version
python --version
python -m pip check
python -c 'import sys, yaml, ansible; assert sys.version_info[:2] == (3, 13); assert yaml.__version__ == "6.0.3"; print("Python imports OK")'
ansible-playbook --version
go version
helm version --short
kubectl version --client
talosctl version --client
promtool --version
systemd-repart --version
mkfs.btrfs --version
sfdisk --version
rsync --version

# Mirror the production test: a regular, disposable sparse image, never a
# device. Fail if offline repart or filesystem creation cannot run as UID 1000.
python - <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

work = Path('/work')
if work.resolve() != work or not work.is_dir() or work.is_symlink():
    raise SystemExit('Expected dedicated /work mount')
with tempfile.TemporaryDirectory(prefix='repart-test-', dir=work) as directory:
    root = Path(directory)
    if root.resolve() != root or root.parent != work or root.is_symlink():
        raise SystemExit('Unexpected test directory')
    definitions = root / 'definitions'
    definitions.mkdir()
    (definitions / '50-test.conf').write_text(
        '[Partition]\nType=linux-generic\nLabel=runner-test\n'
        'UUID=12345678-1234-4234-8234-123456789abc\nFormat=btrfs\nFactoryReset=no\n')
    image = root / 'disk.raw'
    with image.open('xb') as stream:
        stream.truncate(400 * 1024 * 1024)
    command = ['systemd-repart', '--offline=yes', '--dry-run=no', '--empty=require',
               '--factory-reset=no', '--discard=no', f'--definitions={definitions}', str(image)]
    subprocess.run(command, check=True, timeout=60)
    output = subprocess.check_output(['sfdisk', '--json', str(image)], text=True)
    partition = json.loads(output)['partitiontable']['partitions'][0]
    assert partition['uuid'].lower() == '12345678-1234-4234-8234-123456789abc'
    result = subprocess.check_output(['blkid', '--probe', '--offset', str(partition['start'] * 512),
                                      '--output', 'export', str(image)], text=True)
    assert 'TYPE=btrfs' in result and 'LABEL=runner-test' in result
    with image.open('rb') as stream:
        before = hashlib.file_digest(stream, 'sha256').digest()
    again = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    assert again.returncode != 0
    with image.open('rb') as stream:
        assert hashlib.file_digest(stream, 'sha256').digest() == before
    print('Unprivileged offline repart and second-run rejection OK')
PY
