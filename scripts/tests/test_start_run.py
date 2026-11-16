"""The campaign launcher: what it would run, what it would write, and the take-over of a held guard.

Every pwsh child is started without a console window and with a bound on its run time.
"""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'scripts' / 'start-run.ps1'
PWSH = shutil.which('pwsh') or 'pwsh'
NO_WINDOW = getattr(subprocess, 'CREATE_NO_WINDOW', 0)


class StartRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / 'build').mkdir()
        (self.root / 'docs').mkdir()
        (self.root / 'docs/run.md').write_text('# Run\n')

    def tearDown(self):
        self.tmp.cleanup()

    def run_launcher(self, *args):
        result = subprocess.run(
            [PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(SCRIPT),
             '-StateRoot', str(self.root / 'build'), *args],
            capture_output=True, text=True, encoding='utf-8', timeout=120, creationflags=NO_WINDOW,
            env={k: v for k, v in __import__('os').environ.items() if k != 'CONCLAVE_AUTOMATION'})
        return result.returncode, result.stdout

    def test_dry_run_names_each_runners_command(self):
        code, out = self.run_launcher('-DryRun')
        self.assertEqual(code, 0, out)
        self.assertIn('claude --session-id', out)
        self.assertIn('--model opus --effort medium --name ScratchPad Claude campaign', out)
        self.assertIn('process-phase', out)
        self.assertIn('No run guard was active', out)
        code, out = self.run_launcher('-DryRun', '-Runner', 'agy')
        self.assertEqual(code, 0, out)
        self.assertIn('agy --model=gemini-pro-orchestrator --dangerously-skip-permissions', out)

    def test_shortcut_dry_run_writes_nothing(self):
        desktop = self.root / 'desktop'
        desktop.mkdir()
        code, out = self.run_launcher('-InstallShortcut', '-DryRun', '-ShortcutDir', str(desktop),
                                      '-IconDir', str(self.root / 'icons'))
        self.assertEqual(code, 0, out)
        self.assertIn('ScratchPad Claude campaign.lnk', out)
        self.assertIn('ScratchPad Carbon campaign.lnk', out)
        self.assertEqual(list(desktop.iterdir()), [])
        self.assertFalse((self.root / 'icons').exists())

    def test_take_over_ends_the_held_guard_before_the_agent_starts(self):
        acquired = subprocess.run(
            [sys.executable, str(ROOT / 'scripts/claude_campaign.py'), '--root', str(self.root), 'acquire',
             '--session', 'earlier-session-0001', '--run-file', 'docs/run.md', '--scope', 'plan'],
            capture_output=True, text=True, timeout=60, creationflags=NO_WINDOW)
        self.assertEqual(acquired.returncode, 0, acquired.stderr)
        code, out = self.run_launcher('-DryRun')
        self.assertIn('active for session earlier-session-0001', out)
        # A stand-in agent that exits at once: the launcher must end the guard first and pass the goal through.
        stand_in = self.root / 'agent.cmd'
        stand_in.write_text('@echo agent-started\r\n')
        code, out = self.run_launcher('-TakeOver', '-ClaudePath', str(stand_in))
        self.assertEqual(code, 0, out)
        self.assertIn('ended with reason handoff', out)
        self.assertIn('agent-started', out)
        state = json.loads((self.root / 'build/claude-campaign/state.json').read_text())
        self.assertEqual((state['status'], state['reason']), ('ended', 'handoff'))

    def test_scheduled_task_start_is_refused(self):
        result = subprocess.run(
            [PWSH, '-NoLogo', '-NoProfile', '-NonInteractive', '-File', str(SCRIPT), '-DryRun'],
            capture_output=True, text=True, encoding='utf-8', timeout=120, creationflags=NO_WINDOW,
            env={**__import__('os').environ, 'CONCLAVE_AUTOMATION': 'nightly'})
        self.assertEqual(result.returncode, 2, result.stdout)
        self.assertIn('start refused', result.stdout)


if __name__ == '__main__':
    unittest.main()
