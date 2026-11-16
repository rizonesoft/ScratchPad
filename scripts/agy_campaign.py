"""Campaign lifecycle for the Carbon writer (Google Antigravity, `agy`).

The lifecycle is the Claude writer's (scripts/claude_campaign.py), loaded here as a private module so this runner
keeps its own state under build/agy-campaign/ and shares only the writer interlock. What differs is Antigravity's
Stop payload: it names the session `conversationId`, is held with `{"decision": "continue"}`, reports an operator
cancel as `terminationReason: USER_CANCELED` (which pauses the run, as an interrupt does) and sends
`fullyIdle: false` while the agent is still working (which is not a stop).
"""
import importlib.util
from pathlib import Path
import sys

_spec = importlib.util.spec_from_file_location('scratchpad_agy_campaign_core', Path(__file__).with_name('claude_campaign.py'))
core = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(core)
core.HARNESS, core.OTHER, core.SESSION_ENV = 'agy', 'claude', 'ANTIGRAVITY_CONVERSATION_ID'
_lifecycle_hook = core.hook


def hook(root, event):
    if not isinstance(event, dict): return {}
    if 'conversationId' in event:
        event.setdefault('session_id', event['conversationId'])
        if event.get('terminationReason') == 'USER_CANCELED':
            event['hook_event_name'] = 'Interrupt'
        elif event.get('fullyIdle') is False:
            return {}
        else:
            event.setdefault('hook_event_name', 'Stop')
    result = _lifecycle_hook(root, event)
    if result.get('decision') == 'block' and event.get('hook_event_name') == 'Stop':
        result = {**result, 'decision': 'continue'}
    return result


core.hook = hook

if __name__ == '__main__':
    sys.exit(core.main())
