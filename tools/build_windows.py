"""Reproducible Godot 4.4.1 Windows export. Python standard library only."""
from __future__ import annotations
import argparse, io, json, os, pathlib, platform, re, shutil, subprocess, urllib.request, zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION = '4.4.1-stable'
BASE = f'https://github.com/godotengine/godot/releases/download/{VERSION}/'
CACHE = ROOT/'.build-cache'

class RemoteZip(io.RawIOBase):
    """Read the central directory and just the chosen Windows binary via ranges."""
    def __init__(self, url):
        with urllib.request.urlopen(urllib.request.Request(url, method='HEAD'), timeout=60) as response:
            self.url = response.url
            self.size = int(response.headers['Content-Length'])
        self.pos = 0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.pos
    def seek(self, offset, whence=0):
        self.pos = offset if whence == 0 else self.pos+offset if whence == 1 else self.size+offset
        return self.pos
    def read(self, size=-1):
        if size < 0: size = self.size-self.pos
        size = min(size, self.size-self.pos)
        if not size: return b''
        request = urllib.request.Request(self.url, headers={'Range': f'bytes={self.pos}-{self.pos+size-1}'})
        with urllib.request.urlopen(request, timeout=90) as response:
            if response.status != 206:
                raise RuntimeError('Server ignored the range request. Download the export templates manually and use --template.')
            content = response.read()
        self.pos += len(content)
        return content

def prepare(godot=None, template=None):
    CACHE.mkdir(exist_ok=True)
    if godot:
        executable = pathlib.Path(shutil.which(godot) or godot).resolve()
    else:
        system = platform.system()
        if system not in ('Windows', 'Linux'):
            raise RuntimeError('On this system, provide the Godot 4.4.1 executable with --godot.')
        suffix = 'win64.exe' if system == 'Windows' else 'linux.x86_64'
        executable = CACHE/f'Godot_v{VERSION}_{suffix}'
        if not executable.exists():
            archive = CACHE/'editor.zip'
            name = f'Godot_v{VERSION}_win64.exe.zip' if system == 'Windows' else f'Godot_v{VERSION}_linux.x86_64.zip'
            print('Downloading official editor…', flush=True)
            urllib.request.urlretrieve(BASE+name, archive)
            with zipfile.ZipFile(archive) as package: package.extractall(CACHE)
            executable.chmod(0o755)
    templates = ROOT/'.templates'
    templates.mkdir(exist_ok=True)
    target = templates/'windows_release_x86_64.exe'
    if template:
        source = pathlib.Path(template).resolve()
        if source != target.resolve(): shutil.copyfile(source, target)
    elif not target.exists():
        print('Downloading official Windows export template…', flush=True)
        temp = target.with_suffix('.tmp')
        with zipfile.ZipFile(RemoteZip(BASE+f'Godot_v{VERSION}_export_templates.tpz')) as package:
            info = next(i for i in package.infolist() if i.filename.endswith('/windows_release_x86_64.exe'))
            with package.open(info) as source, open(temp, 'wb') as out:
                shutil.copyfileobj(source, out, 4*1024*1024)
        temp.replace(target)
    result = subprocess.run([str(executable), '--version'], capture_output=True, text=True, check=True)
    if not result.stdout.startswith('4.4.1.stable'):
        raise RuntimeError('Use the pinned Godot 4.4.1 stable editor with its matching template.')
    (CACHE/'runtime.json').write_text(json.dumps({'godot': str(executable)}))
    return executable

def build(executable):
    output = ROOT/'build'/'AfterHours'
    output.mkdir(parents=True, exist_ok=True)
    def run(args):
        result = subprocess.run([str(executable), '--headless', '--path', str(ROOT), *args],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        print(result.stdout, end='')
        # Godot 4.4.1's headless editor cannot render import thumbnails.
        # Only this exact upstream diagnostic is non-fatal; all other errors fail.
        # https://github.com/godotengine/godot/issues/108994
        checked = re.sub(r'ERROR: Parameter "t" is null\.\n\s+at: texture_2d_get \(servers/rendering/dummy/storage/texture_storage\.h:\d+\)\n', '', result.stdout)
        if result.returncode or 'SCRIPT ERROR' in checked or '\nERROR:' in checked:
            raise RuntimeError('Godot import/export failed; see the log above.')
    run(['--editor', '--import', '--quit'])
    run(['--export-release', 'Windows Desktop', str(output/'AfterHours.exe')])
    if (output/'AfterHours.exe').read_bytes()[:2] != b'MZ': raise RuntimeError('No Windows executable was produced.')
    if not (output/'AfterHours.pck').exists(): raise RuntimeError('Game data pack is missing.')
    shutil.copyfile(ROOT/'README.md', output/'READ-ME.md')
    for filename in ['GODOT-LICENSE.txt', 'GODOT-COPYRIGHT.txt', 'ASSET-LICENSES.txt']:
        shutil.copyfile(ROOT/'docs'/filename, output/filename)
    archive = ROOT/'build'/'AfterHours-Windows.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as package:
        for path in sorted(output.rglob('*')):
            if path.is_file(): package.write(path, pathlib.Path('AfterHours')/path.relative_to(output))
    print(f'BUILT: {archive} ({archive.stat().st_size:,} bytes)', flush=True)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--godot')
    parser.add_argument('--template')
    parser.add_argument('--prepare-only', action='store_true')
    args = parser.parse_args()
    executable = prepare(args.godot, args.template)
    if not args.prepare_only: build(executable)

