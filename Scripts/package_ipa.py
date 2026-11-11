#!/usr/bin/env python3
"""Package a compiled, unsigned LumaBasic device app; never compile or sign it."""
import argparse
import hashlib
from pathlib import Path
import plistlib
import struct
import zipfile


def package(app: Path, output: Path) -> None:
    if not app.is_dir() or app.suffix != '.app':
        raise ValueError('Expected a compiled .app directory from the iPhoneOS build.')
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise ValueError('Only an iPhone device build can be packaged, not a simulator build.')
    name = info.get('CFBundleExecutable', '')
    if not name or Path(name).name != name:
        raise ValueError('Missing or invalid app executable name.')
    executable = app / name
    with executable.open('rb') as source:
        header = source.read(12)
    # This workflow builds one thin arm64 device executable, never a simulator or source ZIP.
    if len(header) != 12 or struct.unpack('<II', header[:8]) != (0xFEEDFACF, 0x0100000C):
        raise ValueError('The executable must be a compiled arm64 Mach-O binary.')
    if not executable.stat().st_mode & 0o111:
        raise ValueError('The app executable is missing its execute permission.')
    if (app / 'PlugIns').exists():
        raise ValueError('Use the LumaBasic scheme; this route does not sign extensions.')
    files = sorted(path for path in app.rglob('*') if path.is_file() or path.is_symlink())
    if any(path.is_symlink() for path in files):
        raise ValueError('Unexpected symlink in the standalone Basic app; inspect the build.')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix('.ipa.tmp')
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                archive.write(path, (Path('Payload') / app.name / path.relative_to(app)).as_posix())
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError('IPA integrity check failed.')
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (output.parent / 'SHA256.txt').write_text(f'{digest}  {output.name}\n')
    (output.parent / 'READ_ME.txt').write_text(
        'Luma Sleep: compiled iPhone app, UNSIGNED.\n'
        'Extract the GitHub artifact ZIP once. Keep the .ipa intact.\n'
        'Use Sideloadly on Windows to sign and install with your own Apple Account.\n'
        'No Apple password or signing certificate was used by this build.\n'
        'See WINDOWS_START_HERE.md in the source project for the full steps.\n'
        'A successful build does not verify physical-device or overnight behavior.\n'
    )
    print(f'Created unsigned IPA: {output} ({output.stat().st_size:,} bytes)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.app, args.output)
