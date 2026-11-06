"""Current policy behavior, independent of historical dispatcher fixtures."""
import copy
import importlib.util
from pathlib import Path
import unittest
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('policy_dispatch', ROOT / 'scripts/review-dispatch.py')
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


def policy():
    return {
        'completion_order': 'last', 'max_low_rounds': 8, 'severity_stop_after': 0,
        'plan': {'effort': 'medium', 'lenses': ['plan']},
        'completion': {'effort': 'medium'},
        'rounds': [{'effort': 'medium', 'lenses': ['adversarial']}],
        'rotation': {'effort': 'low', 'lenses': ['quality', 'record']},
        'escalation': {'effort': 'low', 'lenses': ['adversarial']},
    }


def entry(kind='round', clean=False):
    review = 'HIGHEST: none\nOVERALL: approve' if clean else 'HIGHEST: P2\nOVERALL: needs-attention'
    if kind == 'plan':
        review = 'HIGHEST: none\nPLAN: complete\nOVERALL: approve'
    if kind == 'completion':
        review = 'COMPLETION: complete'
    return dict(writer='codex', writer_model='gpt-6-astra', reviewer='argon',
                cli='agy', model='gemini-4-argon-medium', review=review,
                policy='a'*40, execution='returned', candidate='b'*40)


class CurrentPolicy(unittest.TestCase):
    def test_malformed_lineage_refuses_without_traceback(self):
        with self.assertRaisesRegex(d.Refused, 'malformed'):
            d.record_policy(d.load_pin(), None)

    def test_failed_medium_attempt_replays_at_medium(self):
        pin = d.load_pin()
        found = dict(plans=[], rounds=[], completions=[])
        for index, kind in enumerate(('plan', 'round', 'round')):
            e = entry(kind, clean=True)
            e.update(_line=index, attempt_reviewer='argon', attempt_model=e['model'],
                     attempt_cli='agy', effort='medium',
                     lenses=['plan'] if kind == 'plan' else ['adversarial'])
            if index == 1:
                e.update(reviewer=None, execution='timeout', review='No review.')
            found['plans' if kind == 'plan' else 'rounds'].append(e)
        d.validate_current_record(pin, found)
        self.assertEqual(d.scheduled(pin['schedule'], 'round', found['rounds'][:1], False)['effort'],
                         'medium')


    def test_record_roundtrip_and_order_replay(self):
        pin = d.load_pin()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'review.md'
            for kind in ('plan', 'round', 'completion'):
                e = entry(kind, clean=True)
                e.update(attempt_reviewer='argon', attempt_model=e['model'], attempt_cli='agy',
                         failover=[], effort='medium', lenses=['plan'] if kind == 'plan' else
                         ['adversarial'] if kind == 'round' else [])
                if kind == 'round':
                    d.record(path, e, '2026-11-06T00:00:00Z')
                else:
                    d.record_completion(path, e, '2026-11-06T00:00:00Z', 'b'*40, kind)
            found = d.read_findings(path.read_text())
            d.validate_current_record(pin, found)
            self.assertEqual(found['plans'][0]['writer_model'], 'gpt-6-astra')
            found['completions'][0]['_line'] = 0
            with self.assertRaises(d.Refused):
                d.validate_current_record(pin, found)


    def test_default_and_invalid_caps(self):
        s = policy()
        del s['max_low_rounds']
        d.check_schedule(s, {'agy'})
        self.assertEqual(d.schedule_cap(s), 9)
        for invalid in (True, -1, 33, '8'):
            s['max_low_rounds'] = invalid
            with self.assertRaises(d.Refused):
                d.check_schedule(s, {'agy'})

    def test_sequence_clean_and_exhaustion(self):
        found = dict(plans=[entry('plan')], rounds=[], completions=[])
        with self.assertRaises(d.Refused):
            d.check_sequence(policy(), 'completion', found, 'codex', 'gpt-6-astra')
        found['rounds'] = [entry() for _ in range(9)]
        for kind in ('round', 'completion'):
            with self.assertRaises(d.Refused):
                d.check_sequence(policy(), kind, found, 'codex', 'gpt-6-astra')
        found['rounds'][-1] = entry(clean=True)
        d.check_sequence(policy(), 'completion', found, 'codex', 'gpt-6-astra')
        with self.assertRaises(d.Refused):
            d.check_sequence(policy(), 'round', found, 'codex', 'gpt-6-astra')

    def test_missing_or_changed_writer_and_plan_refused(self):
        found = dict(plans=[entry('plan')], rounds=[], completions=[])
        for model in (None, 'different-model'):
            with self.assertRaises(d.Refused):
                d.check_sequence(policy(), 'round', found, 'codex', model)
        found['plans'] = []
        with self.assertRaises(d.Refused):
            d.check_sequence(policy(), 'round', found, 'codex', 'gpt-6-astra')

    def test_failed_attempt_does_not_spend_round(self):
        rounds = [entry(), dict(entry(), reviewer=None, execution='timeout')]
        step = d.scheduled(policy(), 'round', rounds, False)
        self.assertEqual((step['position'], step['effort']), (2, 'low'))

    def test_clean_is_explicit_and_not_contradictory(self):
        self.assertTrue(d.clean('HIGHEST: none\nOVERALL: approve'))
        self.assertFalse(d.clean('OVERALL: approve'))
        self.assertFalse(d.clean('HIGHEST: P1\nHIGHEST: none\nOVERALL: approve'))

    def test_variants_and_recorded_missing_execution(self):
        pin = d.load_pin()
        self.assertEqual(pin['routes']['codex'], ['argon'])
        for writer in ('claude', 'gemini'):
            self.assertEqual(pin['routes'][writer], ['astra'])
        with patch.object(d, 'find_cli', return_value=None):
            result = d.review(pin, 'codex', ROOT / 'docs/plan-review-prompt.md', 1,
                              dict(effort='low', lenses=[], position=2, escalated=False))
        self.assertEqual(result['attempt_model'], 'gemini-4-argon-low')
        self.assertEqual(result['execution'], 'missing')
        self.assertIsNone(result['reviewer'])

    def test_invocation_selects_low_variant_and_records_simulated_result(self):
        pin = d.load_pin()
        seen = []
        def run(argv, stdin, timeout, watched):
            seen.append(argv)
            watched[0].write_text(__import__('json').dumps({'status': 'SUCCESS', 'response': 'HIGHEST: none\nOVERALL: approve'}), encoding='utf-8')
            return 0, None
        with patch.object(d, 'find_cli', return_value='agy.exe'), patch.object(d, 'run', side_effect=run):
            result = d.review(pin, 'codex', ROOT / 'docs/plan-review-prompt.md', 1,
                              dict(effort='low', lenses=[], position=2, escalated=False))
        self.assertEqual(seen[0][seen[0].index('--model')+1], 'gemini-4-argon-low')
        self.assertEqual(result['model'], 'gemini-4-argon-low')
        self.assertEqual(result['execution'], 'returned')


class RuntimeCeiling(unittest.TestCase):
    def test_antigravity_uses_scoped_session_permissions(self):
        import json,re
        settings=ROOT/'.conclave/antigravity-review-settings.json'
        policy=json.loads(settings.read_text())['permissions']
        self.assertEqual(set(policy['deny']),{'write_file(*)','edit_file(*)'})
        patterns=[rule[len('command(regex:'):-1] for rule in policy['allow']]
        for command in ('git reset --hard','git status --short; Remove-Item x','git --no-pager diff --no-ext-diff --no-textconv HEAD && whoami'):
            self.assertFalse(any(re.search(p,command) for p in patterns))
        self.assertTrue(any(re.search(p,'git status --short') for p in patterns))
        argv,_=d.command(d.load_pin()['reviewers']['argon'],'agy.exe','review',Path('p'),Path('o'),30)
        self.assertEqual(Path(argv[argv.index('--settings')+1]),settings)
        self.assertNotIn('--dangerously-skip-permissions',argv)

    def test_contradictory_highest_with_comment_is_not_clean(self):
        self.assertFalse(d.clean('HIGHEST: P1 - race\nHIGHEST: none\nOVERALL: approve'))

    def test_missing_writer_refuses(self):
        with self.assertRaises(d.Refused):
            d.validate_current_record(d.load_pin(),dict(plans=[{'_line':1}],rounds=[],completions=[]))

    def test_live_default_above_medium_is_refused(self):
        text=(ROOT/'.conclave/reviewers.toml').read_text(encoding='utf-8').replace('effort = "medium"','effort = "high"',1)
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'pin.toml';path.write_text(text)
            with self.assertRaisesRegex(d.Refused,'medium'): d.load_pin(path)

    def test_plan_gaps_must_be_fixed_before_rounds(self):
        e=entry('plan',clean=True); e['review']='HIGHEST: P2\nPLAN: gaps\nOVERALL: needs-attention'
        with self.assertRaisesRegex(d.Refused,'plan.*complete'):
            d.check_sequence(policy(),'round',dict(plans=[e],rounds=[],completions=[]),'codex','gpt-6-astra')

    def test_historical_high_effort_cannot_launch(self):
        pin=d.load_pin(); pin['reviewers']['astra']['effort']='high'
        with patch.object(d,'find_cli') as find:
            with self.assertRaisesRegex(d.Refused,'exceed medium'):
                d.review(pin,'claude',ROOT/'docs/plan-review-prompt.md',1)
            find.assert_not_called()

    def test_mislabeled_argon_variant_cannot_launch(self):
        pin=d.load_pin(); pin['reviewers']['argon']['models_by_effort']['low']='gemini-4-argon-high'
        with patch.object(d,'find_cli') as find:
            with self.assertRaises(d.Refused):
                d.review(pin,'codex',ROOT/'docs/plan-review-prompt.md',1,dict(effort='low',lenses=[],position=2,escalated=False))
            find.assert_not_called()

    def test_antigravity_failure_envelope_is_not_review(self):
        def run(argv,stdin,timeout,watched):
            watched[0].write_text('{"status":"FAILED","response":"looks like approval"}')
            return 0,None
        with patch.object(d,'find_cli',return_value='agy.exe'),patch.object(d,'run',side_effect=run):
            result=d.review(d.load_pin(),'codex',ROOT/'docs/plan-review-prompt.md',1,dict(effort='medium',lenses=[],position=1,escalated=False))
        self.assertIsNone(result['reviewer'])

class ClaudeNeverReviews(unittest.TestCase):
    SONNET = '[reviewers.sonnet]\ncli = "claude"\nmodel = "claude-sonnet-5-5"\neffort = "high"\n\n'

    def pin_text(self, routed):
        text = (ROOT / '.conclave/reviewers.toml').read_text(encoding='utf-8')
        if routed:
            self.assertEqual(text.count('gemini = ["astra"]'), 1)
            text = text.replace('gemini = ["astra"]', 'gemini = ["sonnet"]')
        head, tail = text.split('[routes]', 1)
        return head + self.SONNET + '[routes]' + tail

    def test_the_committed_pin_names_no_claude_reviewer(self):
        self.assertNotIn('claude', {r['cli'] for r in d.load_pin()['reviewers'].values()})

    def test_a_live_pin_with_a_claude_reviewer_refuses_routed_or_not(self):
        for routed in (True, False):
            with self.subTest(routed=routed), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'reviewers.toml'
                path.write_text(self.pin_text(routed), encoding='utf-8')
                with self.assertRaisesRegex(d.Refused, 'sonnet.*Claude is never a reviewer'):
                    d.load_pin(path)

    def test_a_past_pin_naming_claude_still_loads_for_replay(self):
        pin = d.load_pin(data=self.pin_text(True).encode('utf-8'))
        self.assertEqual(pin['reviewers']['sonnet']['cli'], 'claude')

    def test_a_replayed_claude_route_launches_nothing(self):
        pin = d.load_pin(data=self.pin_text(True).encode('utf-8'))
        with patch.object(d, 'find_cli', return_value='claude.exe') as found, patch.object(d, 'run') as run:
            with self.assertRaisesRegex(d.Refused, 'Claude is never a reviewer'):
                d.review(pin, 'gemini', ROOT / 'docs/plan-review-prompt.md', 1)
        found.assert_not_called()
        run.assert_not_called()

    def test_claude_can_still_write(self):
        self.assertEqual(d.load_pin()['routes']['claude'], ['astra'])


if __name__ == '__main__':
    unittest.main()
