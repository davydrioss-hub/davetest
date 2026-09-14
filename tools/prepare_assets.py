"""Fetch the pinned CC0 material library at build time. The shipped game is offline."""
import concurrent.futures
import hashlib
import json
import pathlib
import shutil
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]

def prepare_assets():
    manifest = json.loads((ROOT / 'tools/assets-manifest.json').read_text())
    def fetch(entry):
        path = ROOT / entry['path']
        def valid(p):
            if not p.exists() or p.stat().st_size != entry['bytes']:return False
            with p.open('rb') as stream:return hashlib.file_digest(stream, 'sha256').hexdigest() == entry['sha256']
        config = path.with_suffix(path.suffix + '.import')
        preset = ROOT / 'tools/material-imports' / config.name
        if not config.exists() and preset.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(preset, config)
        if valid(path):
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(path.suffix + '.download')
        request = urllib.request.Request(entry['url'], headers={'User-Agent': 'AfterHoursGame/0.3 asset-download'})
        with urllib.request.urlopen(request, timeout=120) as response, temp.open('wb') as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)
        if not valid(temp):
            temp.unlink(missing_ok=True)
            raise RuntimeError('Material checksum mismatch: ' + entry['path'])
        temp.replace(path)
        print('Prepared ' + entry['path'], flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(fetch, manifest['files']))

if __name__ == '__main__':
    prepare_assets()
