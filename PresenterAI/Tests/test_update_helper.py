"""Exercise the production install/rollback script using inert test bundles.
Only the external 'open' boundary is stubbed: no user's app is launched.
"""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).parents[1] / 'Scripts' / 'install-update.sh'

class UpdateHelperTests(unittest.TestCase):
    def run_update(self, succeeds):
        with tempfile.TemporaryDirectory(prefix='sa-cook-updater-test-') as root:
            root = pathlib.Path(root)
            work = root / '.sa-cook-stage-test'
            work.mkdir()
            target = root / 'SA Cook Assistant.app'
            target.mkdir()
            (target / 'old-data').write_text('original')
            staged = work / 'new.app'
            binary = staged / 'Contents' / 'MacOS' / 'PresenterAI'
            binary.parent.mkdir(parents=True)
            binary.write_text('#!/bin/sh\nprintf ready > "${1#--sa-cook-update-health=}"\nsleep 2\n' if succeeds else '#!/bin/sh\nexit 1\n')
            binary.chmod(0o700)
            script = root / 'helper.sh'
            script.write_text(SCRIPT.read_text().replace('/usr/bin/open', '/usr/bin/true'))
            result = subprocess.run(['/bin/sh', str(script), str(target), str(staged), '999999999', str(work), str(root / 'update.log')], timeout=10)
            if succeeds:
                self.assertEqual(result.returncode, 0)
                self.assertTrue((target / 'Contents' / 'MacOS' / 'PresenterAI').exists())
                self.assertEqual((work / 'previous.app' / 'old-data').read_text(), 'original')
                self.assertTrue((work / 'ready').exists())
            else:
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual((target / 'old-data').read_text(), 'original')
                self.assertTrue((work / 'failed.app').exists())
    def test_success_preserves_backup_until_new_app_ready(self):
        self.run_update(True)
    def test_failed_launch_restores_old_app(self):
        self.run_update(False)

if __name__ == '__main__':
    unittest.main()
