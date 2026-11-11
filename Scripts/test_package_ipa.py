"""Packaging guards only. Synthetic fixtures are NOT runnable iOS apps."""
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

from package_ipa import package


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.app = root / 'LumaSleep.app'
        self.app.mkdir()
        self.output = root / 'export' / 'test-only.ipa'
        self.info = {'CFBundleSupportedPlatforms': ['iPhoneOS'], 'CFBundleExecutable': 'LumaSleep'}
        self.write_info()
        executable = self.app / 'LumaSleep'
        executable.write_bytes(struct.pack('<III', 0xFEEDFACF, 0x0100000C, 0))
        executable.chmod(0o755)

    def write_info(self):
        (self.app / 'Info.plist').write_bytes(plistlib.dumps(self.info))

    def test_payload_and_permissions(self):
        package(self.app, self.output)
        with zipfile.ZipFile(self.output) as archive:
            item = archive.getinfo('Payload/LumaSleep.app/LumaSleep')
            self.assertTrue((item.external_attr >> 16) & 0o111)
            self.assertIn('Payload/LumaSleep.app/Info.plist', archive.namelist())

    def test_simulator_rejected(self):
        self.info['CFBundleSupportedPlatforms'] = ['iPhoneSimulator']
        self.write_info()
        with self.assertRaisesRegex(ValueError, 'device build'):
            package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_source_instead_of_binary_rejected(self):
        (self.app / 'LumaSleep').write_text('print("source code is not a binary")')
        with self.assertRaisesRegex(ValueError, 'Mach-O'):
            package(self.app, self.output)

    def test_extension_build_rejected(self):
        (self.app / 'PlugIns').mkdir()
        with self.assertRaisesRegex(ValueError, 'LumaBasic'):
            package(self.app, self.output)


if __name__ == '__main__':
    unittest.main()
