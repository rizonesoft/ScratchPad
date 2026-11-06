"""Both harnesses obey the same lifecycle contract without runtime imports."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]

class Campaign(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.modules = {}
        for harness in ('codex', 'claude'):
            spec = importlib.util.spec_from_file_location(harness, ROOT / 'scripts' / f'{harness}_campaign.py')
            m = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(m)
            self.modules[harness] = m
        (self.root / 'docs').mkdir()
        (self.root / 'docs/run.md').write_text('# Run\n')
    def tearDown(self):
        self.tmp.cleanup()
    def acquire(self, harness='codex'):
        return self.modules[harness].acquire(self.root, 'owner', 'docs/run.md', 'plan', None)
    def test_only_one_writer_across_harnesses(self):
        self.acquire()
        with self.assertRaises(ValueError): self.acquire('claude')
        self.modules['codex'].end(self.root, 'owner', 'operator-stop')
        self.acquire('claude')
    def test_wrong_session_cannot_end(self):
        self.acquire()
        with self.assertRaises(ValueError): self.modules['codex'].end(self.root, 'other', 'operator-stop')
    def test_wrong_session_and_subagents_never_block(self):
        self.acquire()
        m=self.modules['codex']
        self.assertEqual(m.hook(self.root, {'session_id':'other','hook_event_name':'Stop'}), {})
    def test_stop_continues_and_three_unchanged_stops_stall(self):
        for name,m in self.modules.items():
            with self.subTest(harness=name):
                self.acquire(name)
                with patch.object(m,'fingerprint',return_value='same'), patch.object(m,'runnable',return_value=True):
                    for _ in range(3): self.assertEqual(m.hook(self.root,{'session_id':'owner','hook_event_name':'Stop'})['decision'],'block')
                    self.assertEqual(m.hook(self.root,{'session_id':'owner','hook_event_name':'Stop'}),{})
                self.assertEqual(m.read(self.root)['status'],'stalled')
                self.assertIsNone(m.heartbeat(self.root,'owner',m.read(self.root)['generation'],send=False))
    def test_interrupt_and_session_end_pause(self):
        for event in ('Interrupt','SessionEnd'):
            state=self.acquire()
            m=self.modules['codex']
            m.hook(self.root,{'session_id':'owner','hook_event_name':event})
            self.assertEqual(m.read(self.root)['status'],'paused')
            self.assertIsNone(m.heartbeat(self.root,'owner',state['generation'],send=False))
    def test_stale_generation_message_is_rejected(self):
        state=self.acquire(); m=self.modules['codex']
        result=m.hook(self.root,{'session_id':'owner','hook_event_name':'UserPromptSubmit','prompt':'SCRATCHPAD_HEARTBEAT stale'})
        self.assertEqual(result['decision'],'block')
        self.assertFalse(m.matches(m.read(self.root),'owner','stale'))
    def test_terminal_marker_must_name_this_run(self):
        state=self.acquire(); m=self.modules['codex']
        (self.root/'docs/run.md').write_text('## Closeout run=wrong\n')
        self.assertFalse(m.terminal(self.root,state))
        (self.root/'docs/run.md').write_text('## Closeout run='+state['run_id']+'\n')
        self.assertTrue(m.terminal(self.root,state))
    def test_heartbeat_deduplicates_until_consumed(self):
        state=self.acquire(); m=self.modules['codex']
        with patch.object(m,'runnable',return_value=True):
            message=m.heartbeat(self.root,'owner',state['generation'],send=False)
            self.assertIn(state['generation'],message)
            self.assertIsNone(m.heartbeat(self.root,'owner',state['generation'],send=False))
            m.hook(self.root,{'session_id':'owner','hook_event_name':'UserPromptSubmit','prompt':message})
            self.assertFalse(m.read(self.root)['pending'])
    def test_failed_queue_reports_degraded(self):
        state=self.acquire(); m=self.modules['codex']
        with patch.object(m,'runnable',return_value=True), patch.object(m,'queue_message',side_effect=RuntimeError('resume failed')):
            with self.assertRaises(RuntimeError): m.heartbeat(self.root,'owner',state['generation'])
        self.assertIn('resume failed',m.read(self.root)['error'])
    def test_path_outside_repository_refused(self):
        with self.assertRaises(ValueError): self.modules['codex'].acquire(self.root,'owner','../outside','plan',None)
    def test_bookkeeping_is_not_progress(self):
        m=self.modules['codex']; self.acquire()
        for args in (['init','-q'],['config','user.email','test@example.invalid'],['config','user.name','Test'],['add','docs/run.md'],['-c','commit.gpgsign=false','commit','-qm','seed']):
            subprocess.run(['git',*args],cwd=self.root,check=True,capture_output=True)
        (self.root/'.gitignore').write_text('build/\n')
        before=m.fingerprint(self.root,'docs/run.md')
        with (self.root/'docs/run.md').open('a') as f: f.write('- bookkeeping: heartbeat\n')
        self.assertEqual(before,m.fingerprint(self.root,'docs/run.md'))
        with (self.root/'docs/run.md').open('a') as f: f.write('Actual gate evidence\n')
        self.assertNotEqual(before,m.fingerprint(self.root,'docs/run.md'))
    def test_phase_scope_uses_scratchpad_heading_and_ready_format(self):
        state=self.acquire(); state.update(scope='phase',phase=1)
        (self.root/'todo').mkdir()
        (self.root/'todo/implementation-plan.md').write_text('### Phase 0 -- Setup\n| `D00 T01 §1` |\n### Phase 1 -- App\n| `D01 T02 §3` |\n',encoding='utf-8')
        m=self.modules['codex']
        with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'00-workspace/TODO-01-x.md §1  first\n','')):
            self.assertFalse(m.runnable(self.root,state))
        with patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'01-core/TODO-02-x.md §3  second\n','')):
            self.assertTrue(m.runnable(self.root,state))

    def test_review_wait_does_not_increment_stall_count(self):
        state=self.acquire(); m=self.modules['codex']
        mark=m.state_path(self.root).parent/'reviews'/'review.json'
        mark.parent.mkdir()
        import os,time
        mark.write_text(json.dumps(dict(session='owner',pid=os.getpid(),deadline=time.time()+60)))
        self.assertEqual(m.hook(self.root,dict(session_id='owner',hook_event_name='Stop')),{})
        self.assertEqual(m.read(self.root)['blocks'],0)
        self.assertIsNone(m.heartbeat(self.root,'owner',state['generation'],send=False))
        mark.write_text(json.dumps(dict(session='other',pid=os.getpid(),deadline=time.time()+60)))
        self.assertFalse(m.review_wait(self.root,state))

    def test_interrupt_cancels_even_with_interlock_held(self):
        self.acquire(); m=self.modules['codex']
        with m.ownership_lock(self.root):
            m.hook(self.root,dict(session_id='owner',hook_event_name='Interrupt'))
        self.assertEqual(m.read(self.root)['status'],'paused')

    def test_native_hook_cli_emits_json_and_respects_owner(self):
        state=self.acquire(); m=self.modules['codex']
        result=subprocess.run([__import__('sys').executable,str(ROOT/'scripts/codex_campaign.py'),'--root',str(self.root),'hook'],
                              input=json.dumps(dict(session_id='owner',hook_event_name='Interrupt')),text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(json.loads(result.stdout),{})
        self.assertEqual(m.read(self.root)['status'],'paused')

    def test_queue_uses_original_thread_and_flags_warning(self):
        m=self.modules['codex']
        with patch.object(m.shutil,'which',return_value='codex.exe'),patch.object(m.subprocess,'run',return_value=subprocess.CompletedProcess([],0,'','warning: failed resume')) as run:
            with self.assertRaises(RuntimeError): m.queue_message(self.root,'original-thread','message')
            self.assertEqual(run.call_args.args[0],['codex.exe','queue','--thread','original-thread','--message','message','--resume'])

    def test_hook_wiring_is_separate_and_preserves_claude_routing(self):
        codex=json.loads((ROOT/'.codex/hooks.json').read_text())['hooks']
        claude=json.loads((ROOT/'.claude/settings.json').read_text())['hooks']
        self.assertIn('Interrupt',codex)
        for name,hooks in [('codex',codex),('claude',claude)]:
            for event in ('Stop','UserPromptSubmit','PostToolUse','SessionEnd'):
                command=hooks[event][0]['hooks'][0]['command']
                self.assertIn(name+'_campaign.py',command)
                self.assertNotIn(('claude' if name=='codex' else 'codex')+'_campaign.py',command)
        self.assertIn('agent_routing.py',claude['PreToolUse'][0]['hooks'][0]['command'])

    def test_dead_owner_stops_watchdog_without_queueing(self):
        state=self.acquire(); module=self.modules['codex']
        with patch.object(module,'process_identity',return_value=None),patch.object(module,'heartbeat') as beat:
            self.assertFalse(module.worker_tick(self.root,'owner',state['generation'],300))
            beat.assert_not_called()
        self.assertEqual(module.read(self.root)['status'],'paused')

    def test_recycled_owner_pid_does_not_resume(self):
        state=self.acquire(); module=self.modules['codex']; state.update(owner_pid=123,owner_identity='old');module.save(self.root,state)
        with patch.object(module,'process_identity',return_value='new'):
            self.assertFalse(module.worker_tick(self.root,'owner',state['generation'],300))

    def test_paused_run_can_end_and_be_reacquired(self):
        old=self.acquire(); module=self.modules['codex']
        module.hook(self.root,dict(session_id='owner',hook_event_name='Interrupt'))
        module.end(self.root,'owner','operator-stop')
        self.assertEqual(module.read(self.root)['status'],'ended')
        new=self.acquire()
        self.assertNotEqual(old['generation'],new['generation'])

    def test_pause_during_slow_stop_cannot_return_continuation(self):
        self.acquire(); module=self.modules['codex']
        def slow_fingerprint(*args):
            module.hook(self.root,dict(session_id='owner',hook_event_name='Interrupt'))
            return 'same'
        with patch.object(module,'runnable',return_value=True),patch.object(module,'fingerprint',side_effect=slow_fingerprint):
            self.assertEqual(module.hook(self.root,dict(session_id='owner',hook_event_name='Stop')),{})
        raw=json.loads(module.state_path(self.root).read_text())
        self.assertEqual(raw['status'],'paused')

    def test_runtime_state_paths_are_independent(self):
        self.assertNotEqual(self.modules['codex'].state_path(self.root), self.modules['claude'].state_path(self.root))

if __name__=='__main__': unittest.main()
