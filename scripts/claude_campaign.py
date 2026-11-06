"""Claude-owned campaign lifecycle. No imports or jobs from the Codex runtime."""
from contextlib import contextmanager
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
import uuid

HARNESS = 'claude'
OTHER = 'codex'
ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'SCRATCHPAD_HEARTBEAT '


def state_path(root):
    return Path(root) / 'build' / f'{HARNESS}-campaign' / 'state.json'


def read(root):
    path = state_path(root)
    state = json.loads(path.read_text(encoding='utf-8')) if path.exists() else None
    if state and state.get('status') == 'active' and (path.parent / ('paused-' + state['generation'])).exists():
        state = {**state, 'status': 'paused', 'pending': False}
    return state


def save(root, state):
    path = state_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    if state.get('status') != 'ended' and (path.parent / ('paused-' + state['generation'])).exists():
        state.update(status='paused', pending=False)
    fd, temp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8', newline='\n') as stream:
            json.dump(state, stream, indent=2)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, path)
    finally:
        if os.path.exists(temp): os.unlink(temp)


@contextmanager
def ownership_lock(root):
    # The sole shared primitive is the writer interlock, not either runtime's state.
    path = Path(root) / 'build' / 'writer-ownership.lock'
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as stream:
        if path.stat().st_size == 0:
            stream.write(b'0'); stream.flush()
        deadline = time.monotonic() + 1
        while True:
            try:
                stream.seek(0)
                if os.name == 'nt':
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() >= deadline: raise ValueError('writer interlock busy')
                time.sleep(.02)
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == 'nt':
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream, fcntl.LOCK_UN)


def contained(root, name):
    root = Path(root).resolve()
    path = (root / name).resolve()
    if not path.is_relative_to(root) or path == root:
        raise ValueError('run file must stay inside the repository')
    return path


def acquire(root, session, run_file, scope, phase):
    if not isinstance(run_file, str) or not run_file:
        raise ValueError("run file is required")
    if not session or scope not in ('plan', 'phase') or (scope == 'phase' and phase is None):
        raise ValueError('session, scope and phase are required')
    path = contained(root, run_file)
    if not path.is_file(): raise ValueError('create the run file before acquiring')
    with ownership_lock(root):
        other = Path(root) / 'build' / f'{OTHER}-campaign' / 'state.json'
        if other.exists() and json.loads(other.read_text(encoding='utf-8')).get('status') == 'active':
            raise ValueError(f'{OTHER} owns the tree; end that run before switching')
        previous = read(root)
        if previous and previous.get('status') == 'active':
            raise ValueError('a run already owns the tree; end it before starting another')
        state = dict(session=session, generation=uuid.uuid4().hex, run_id=uuid.uuid4().hex,
                     run_file=str(path.relative_to(Path(root).resolve())), scope=scope, phase=phase,
                     status='active', blocks=0, fingerprint=None, pending=False, error=None,
                     last_event=time.time(), last_heartbeat=None, worker_pid=None)
        save(root, state)
        return state


def matches(state, session, generation=None):
    return bool(state and state.get('status') == 'active' and state.get('session') == session
                and (generation is None or state.get('generation') == generation))


def end(root, session, reason):
    if reason not in ('operator-stop', 'handoff', 'closeout', 'park', 'stall'):
        raise ValueError('invalid end reason')
    with ownership_lock(root):
        state = read(root)
        if not state or state.get('session') != session: raise ValueError('not the owner')
        if reason == 'closeout' and not terminal(root, state):
            raise ValueError('closeout needs this run id in the run file')
        state.update(status='ended', reason=reason, pending=False)
        save(root, state)
    return state


def terminal(root, state):
    text = contained(root, state['run_file']).read_text(encoding='utf-8')
    return bool(re.search(r'^(?:## Closeout\b|PARKED\b)[^\n]*\brun=' + re.escape(state['run_id']) + r'\b', text, re.M))


def runnable(root, state):
    # ScratchPad's canonical graph emits text, not the SDK JSON format.
    result = subprocess.run([sys.executable, str(Path(root)/'scripts/todo-graph.py'), 'query', 'ready'],
                            cwd=root, capture_output=True, text=True, encoding='utf-8', timeout=15)
    if result.returncode: raise ValueError('ready query failed')
    rows = re.findall(r'^([^\s]+\.md) §(\d+)\s', result.stdout, re.M)
    if state['scope'] == 'plan': return bool(rows)
    plan = (Path(root)/'todo/implementation-plan.md').read_text(encoding='utf-8')
    # Phase headings and section references are read from the canonical projection.
    chunks = re.split(r'^### Phase (\d+)\b[^\n]*\n', plan, flags=re.M)
    wanted = next((chunks[i+1] for i in range(1, len(chunks), 2) if int(chunks[i]) == state['phase']), None)
    if wanted is None: raise ValueError('phase missing from implementation plan')
    for path, section in rows:
        domain = path[:2]
        task = re.search(r'TODO-(\d+)', path).group(1)
        if re.search(rf'\bD{domain}\s+T{task}\s+§{section}\b', wanted): return True
    return False


def fingerprint(root, run_file):
    def git(*args):
        return subprocess.run(['git', *args], cwd=root, capture_output=True, check=True, timeout=15).stdout
    digest = hashlib.sha256(git('rev-parse', 'HEAD'))
    for name in sorted(set(git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0'))):
        if not name: continue
        relative = os.fsdecode(name)
        path = contained(root, relative)
        if relative.replace('\\', '/').startswith('build/'): continue
        data = path.read_bytes() if path.is_file() else b'<deleted>'
        if Path(relative) == Path(run_file):
            data = b'\n'.join(line for line in data.splitlines() if not line.startswith(b'- bookkeeping:'))
        digest.update(name + b'\0' + data + b'\0')
    return digest.hexdigest()


def alive(pid):
    if not isinstance(pid, int) or pid <= 0: return False
    if os.name == 'nt':
        import ctypes
        kernel = ctypes.WinDLL('kernel32', use_last_error=True)
        kernel.OpenProcess.argtypes = [ctypes.c_ulong, ctypes.c_int, ctypes.c_ulong]
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, 0, pid)
        if not handle: return False
        try:
            code=ctypes.c_ulong()
            kernel.GetExitCodeProcess.argtypes=[ctypes.c_void_p,ctypes.POINTER(ctypes.c_ulong)]
            return bool(kernel.GetExitCodeProcess(handle,ctypes.byref(code))) and code.value==259
        finally: kernel.CloseHandle(handle)
    try: os.kill(pid,0); return True
    except OSError: return False


def review_wait(root, state):
    folder=state_path(root).parent/'reviews'
    for path in folder.glob('*.json'):
        try:
            mark=json.loads(path.read_text(encoding='utf-8'))
            if mark.get('session')==state['session'] and mark.get('deadline',0)>time.time() and alive(mark.get('pid')):
                return True
        except (ValueError,OSError,TypeError):
            continue
    return False


def hook(root, event):
    if not isinstance(event, dict): return {}
    session, kind = event.get('session_id'), event.get('hook_event_name')
    prompt = event.get('prompt', '')
    if kind in ('Interrupt', 'SessionEnd'):
        # Cancellation must remain effective even while a slow Stop holds the interlock.
        state = read(root)
        if matches(state, session):
            (state_path(root).parent / ('paused-' + state['generation'])).touch()
            try:
                with ownership_lock(root):
                    current=read(root)
                    if current and current.get('generation') == state['generation']:
                        save(root,current)
            except ValueError:
                pass
        return {}
    with ownership_lock(root):
        state = read(root)
        if kind == 'UserPromptSubmit' and isinstance(prompt, str) and prompt.startswith(PREFIX):
            generation = prompt[len(PREFIX):].split()[0] if prompt[len(PREFIX):].strip() else ''
            if not matches(state, session, generation):
                return {'decision':'block', 'reason':'Discarded an obsolete campaign heartbeat.'}
            state.update(pending=False, last_event=time.time())
            save(root, state)
            return {}
        if not matches(state, session): return {}
        if kind in ('Interrupt', 'SessionEnd'):
            state.update(status='paused', pending=False, reason=kind)
        elif kind != 'Stop':
            state['last_event'] = time.time()
        else:
            if terminal(root, state):
                state.update(status='ended', pending=False, reason='terminal-marker')
            elif review_wait(root, state):
                return {}
            elif not runnable(root, state):
                state.update(status='parked', pending=False, reason='nothing-runnable')
            else:
                current = fingerprint(root, state['run_file'])
                state['blocks'] = state['blocks'] + 1 if state['fingerprint'] == current else 1
                state['fingerprint'] = current
                if state['blocks'] > 3:
                    state.update(status='stalled', pending=False, reason='no-progress')
                else:
                    save(root, state)
                    if not matches(state, session): return {}
                    return {'decision':'block', 'reason':f"Continue the {state['scope']} run {state['run_id']} from {state['run_file']}. Recheck ready work and finish the authorized scope. If the operator asks to pause, end the guard immediately. Do not count bookkeeping as progress."}
        save(root, state)
    return {}


def queue_message(root, session, message):
    raise RuntimeError('Claude heartbeat delivery uses CronCreate in the owning session')


def heartbeat(root, session, generation, send=True):
    with ownership_lock(root):
        state = read(root)
        if not generation or not matches(state, session, generation) or state.get('pending'): return None
        if terminal(root, state) or review_wait(root, state) or not runnable(root, state): return None
        message = PREFIX + generation + f" Resume only if scripts/{HARNESS}_campaign.py status still names this session and generation as active. Continue {state['scope']} in {state['run_file']}; never restart a paused, ended or stalled run."
        state.update(pending=True, last_heartbeat=time.time())
        save(root, state)
        if not matches(state,session,generation): return None
    if send:
        try:
            queue_message(root, session, message)
        except Exception as error:
            with ownership_lock(root):
                state = read(root)
                if matches(state, session, generation):
                    state.update(error=str(error), pending=False, status='degraded')
                    save(root, state)
            raise
    return message



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('action', choices=('acquire','end','status','hook','heartbeat'))
    parser.add_argument('--session', default=os.environ.get('CLAUDE_CODE_SESSION_ID', ''))
    parser.add_argument('--generation')
    parser.add_argument('--run-file')
    parser.add_argument('--scope', choices=('plan','phase'), default='plan')
    parser.add_argument('--phase', type=int)
    parser.add_argument('--reason', default='operator-stop')
    parser.add_argument('--interval', type=int, default=300)
    args = parser.parse_args()
    event = {}
    try:
        if args.action == 'hook':
            event = json.load(sys.stdin)
            print(json.dumps(hook(args.root, event)))
        elif args.action == 'acquire':
            print(json.dumps(acquire(args.root,args.session,args.run_file,args.scope,args.phase)))
        elif args.action == 'end': print(json.dumps(end(args.root,args.session,args.reason)))
        elif args.action == 'status': print(json.dumps(read(args.root)))
        elif args.action == 'heartbeat':
            print(heartbeat(args.root,args.session,args.generation,send=HARNESS=='codex') or '')
        return 0
    except Exception as error:
        if args.action == 'hook':
            # Hook failures release the turn and expose degradation; they never forge progress.
            try:
                with ownership_lock(args.root):
                    state=read(args.root)
                    if state and state.get('session') == event.get('session_id'):
                        state.update(error=str(error), status='degraded', pending=False)
                        save(args.root,state)
            except Exception:
                pass
            print(json.dumps({'systemMessage':f'{HARNESS} campaign guard failed: {type(error).__name__}: {error}'}))
            return 0
        print(f'{HARNESS} campaign: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
