"""Subagent routing for Claude Code sessions (operator direction 2026-10-01).

The lead session delegates bounded read-only work (research, gate runs,
and routine pre-panel review) to the repo agents in `.claude/agents/`,
each pinned to the `sonnet` alias at `high` effort. No routed agent writes:
implementation stays with the lead (operator direction 2026-10-02). This file is the one
source of truth for those pins, in the panel_slots.py pattern: the
closed sets live here, `check` fails when an agent file drifts from
them, and `pre-agent` is the PreToolUse hook body that keeps a session
from silently substituting another model or the inherited lead model.

Commands:
  check [--root DIR]       agent files, hook wiring, and the routing
                           record agree with ROUTED_AGENTS (exit 1 on drift)
  pre-agent                PreToolUse hook for the Agent tool: JSON on
                           stdin, a deny decision on stdout or nothing
  observe <path>           what actually ran: agent type, model ids, and
                           per-turn effort read from a session's subagent
                           transcripts (a session dir, a subagents dir,
                           or one agent-*.jsonl)
  self-test                hermetic cases for all of the above

Routing rules enforced by pre-agent (fail open on a bad payload, like
campaign-stop.ps1; `check` in CI and pre-commit guards the wiring):
  - A routed agent may not carry a `model` override other than its pin.
  - A routed agent is denied while the session env sets
    CLAUDE_CODE_EFFORT_LEVEL to another effort, or sets
    ANTHROPIC_DEFAULT_SONNET_MODEL or CLAUDE_CODE_SUBAGENT_MODEL: those
    override frontmatter and would silently change the pinned model or
    effort. `check` fails when a project settings `env` block sets them,
    or `disableAllHooks` is true (that switches this hook off).
  - An agent defined under `.claude/agents/` (any depth) that is not in
    ROUTED_AGENTS is denied: its own file picks the model.
  - Built-in general-purpose, claude, Explore, Plan, and claude-code-guide
    (or no type) are
    denied unless the call passes `model: "opus"`, which is the visible,
    deliberate stronger-model escalation for consequential review.
  - `fork` (the lead's own model) and every other type pass untouched.

Stdlib only, like todo-graph.py.
"""

from __future__ import annotations

import json
import os
import re
import sys
import tempfile
from collections.abc import Mapping
from dataclasses import dataclass


@dataclass(frozen=True)
class Route:
    model: str
    effort: str


# Closed set. A new routed agent, model, or effort arrives with a live
# `observe` record in docs/agent-routing.md, never by agent-file edit alone.
ROUTED_AGENTS = {
    "sonnet-researcher": Route("sonnet", "high"),
    "sonnet-verifier": Route("sonnet", "high"),
    "sonnet-reviewer": Route("sonnet", "high"),
}
# Routed agents are read-only (operator direction 2026-10-02): none may hold a write tool.
WRITE_TOOLS = frozenset({"Edit", "Write", "NotebookEdit"})
# The only tools a routed agent may list: anything else (an MCP tool that
# writes files, say) is a capability nobody reviewed.
READ_ONLY_TOOLS = frozenset({"Read", "Grep", "Glob", "Bash", "PowerShell", "WebFetch", "WebSearch"})
# The only frontmatter keys a routed agent may carry; `disallowedTools` only narrows.
AGENT_KEYS = frozenset({"name", "description", "model", "effort", "tools", "disallowedTools"})
# Routed agents never spawn agents: the lead owns delegation.
FORBIDDEN_TOOLS = frozenset({"Agent", "Task", "Workflow"})
# Built-ins that inherit the lead model or run a lower one: claude-code-guide
# and Explore answer on Haiku, below the bar for repo research.
BUILTIN_UNROUTED = frozenset({"", "general-purpose", "claude", "Explore", "Plan", "claude-code-guide"})
ESCALATION_MODEL = "opus"
AGENT_TOOL_MATCHER = "Agent|Task"
HOOK_COMMAND_MARK = "scripts/agent_routing.py\" pre-agent"
HOOK_KEYS = frozenset({"type", "command", "timeout"})
RECORD = "docs/agent-routing.md"
# Session env that overrides agent frontmatter (Claude Code model config).
EFFORT_ENV = "CLAUDE_CODE_EFFORT_LEVEL"
ALIAS_ENV = "ANTHROPIC_DEFAULT_SONNET_MODEL"
MODEL_ENVS = (ALIAS_ENV, "CLAUDE_CODE_SUBAGENT_MODEL")
# CLAUDE_CODE_SUBAGENT_MODEL is a fallback below explicit frontmatter; it
# overrides a pinned agent only while this flag forces it (Claude Code
# 2.1.287 refuses an explicit agent model under the flag).
FORCE_ENV = "CLAUDE_CODE_SUBAGENT_MODEL_FORCE"
_FALSY = frozenset({"", "0", "false", "no", "off"})
SETTINGS_FILES = ("settings.json", "settings.local.json")


def routing_table() -> str:
    return "; ".join(f"{name} ({r.model}, {r.effort})" for name, r in ROUTED_AGENTS.items())


def env_overrides(env: Mapping[str, object], efforts: set[str], models: set[str]) -> list[tuple[str, str]]:
    """(variable, value) pairs that would silently change a pinned model or effort.

    ANTHROPIC_DEFAULT_SONNET_MODEL redirects the alias itself, so any value
    counts. CLAUDE_CODE_SUBAGENT_MODEL counts only while FORCE_ENV is set,
    and never when it names the pinned alias.
    """
    forced = str(env.get(FORCE_ENV) or "").strip().lower() not in _FALSY
    found: list[tuple[str, str]] = []
    effort = str(env.get(EFFORT_ENV) or "").strip()
    if effort and any(effort.lower() != pinned for pinned in efforts):
        found.append((EFFORT_ENV, effort))
    for var in MODEL_ENVS:
        value = str(env.get(var) or "").strip()
        if not value:
            continue
        if var == ALIAS_ENV or (forced and any(value.lower() != pinned for pinned in models)):
            found.append((var, value))
    return found


def decide(
    tool_input: dict,
    env: Mapping[str, str] | None = None,
    project_agents: frozenset[str] = frozenset(),
) -> str | None:
    """Deny reason for an Agent call, or None to allow.

    `env` is the session environment (the hook passes os.environ; None means
    empty) and `project_agents` the names defined under `.claude/agents/`.
    """
    env = {} if env is None else env
    kind = str(tool_input.get("subagent_type") or "").strip()
    model = str(tool_input.get("model") or "").strip()
    route = ROUTED_AGENTS.get(kind)
    if route is not None:
        if model and model != route.model:
            return (
                f"{kind} is pinned to {route.model} at {route.effort} effort (scripts/agent_routing.py); "
                f"a model override of '{model}' would silently substitute another model. "
                "Drop the override, or keep the work in the lead session or a fork when it needs a stronger model."
            )
        for var, value in env_overrides(env, {route.effort}, {route.model}):
            shown = f"'{value}'" if var == EFFORT_ENV else "a value"
            return (
                f"{kind} is pinned to {route.model} at {route.effort} effort (scripts/agent_routing.py); "
                f"{var} is set to {shown} in the session environment and would silently change the pinned model or effort. "
                "Unset it for this session, or keep the work in the lead session or a fork."
            )
        return None
    if kind in project_agents:
        return (
            f"{kind} is defined under .claude/agents/ but is not routed (scripts/agent_routing.py): "
            f"its own file picks the model. Use a routed agent instead: {routing_table()}."
        )
    if kind in BUILTIN_UNROUTED:
        if model == ESCALATION_MODEL:
            return None
        label = kind or "general-purpose (default)"
        return (
            f"{label} is not routed in this repo: it inherits the lead model or a lower one. "
            f"Delegate to a repo agent instead: {routing_table()}. "
            f"For deliberate stronger-model review pass model: \"{ESCALATION_MODEL}\" or use a fork (see AGENTS.md, Delegation)."
        )
    return None


def default_root() -> str:
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def project_root(env: Mapping[str, str]) -> str:
    return env.get("CLAUDE_PROJECT_DIR") or default_root()


def run_pre_agent(stdin_text: str, env: Mapping[str, str] | None = None, root: str | None = None) -> str:
    """Hook stdout for one PreToolUse payload; empty means allow. Fails open.

    The hook path defaults `env` to os.environ and `root` to the project root
    (CLAUDE_PROJECT_DIR, else the parent of this script's directory).
    """
    try:
        env = os.environ if env is None else env
        event = json.loads(stdin_text) if stdin_text.strip() else {}
        tool_input = event.get("tool_input") or {}
        if not isinstance(tool_input, dict):
            return ""
        try:
            project_agents = project_agent_names(project_root(env) if root is None else root)
        except Exception:  # an unscannable agents dir never blocks delegation
            project_agents = frozenset()
        reason = decide(tool_input, env, project_agents)
    except Exception:  # fail open: a broken payload never blocks delegation
        return ""
    if reason is None:
        return ""
    return json.dumps(
        {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }
    )


@dataclass(frozen=True)
class Unsupported:
    """A frontmatter value in a shape this parser does not read; never silently accepted."""

    shape: str


_BLOCK_SCALAR = re.compile(r"^[|>][+-]?\d*$")


def _strip_comment(value: str) -> str:
    if value.startswith("#"):
        return ""
    return re.split(r"\s#", value, maxsplit=1)[0].strip()


class _Escaped(ValueError):
    """A double-quoted scalar with an escape sequence: YAML decodes it, this parser does not."""


def _unquote(value: str) -> str:
    """One YAML scalar: matching quotes removed, or a bare value minus a trailing comment."""
    value = value.strip()
    if value[:1] == '"':
        # Escapes count only inside the scalar: a backslash before the
        # closing quote; one in a trailing comment is not part of the value.
        for ch in value[1:]:
            if ch == "\\":
                raise _Escaped(value)
            if ch == '"':
                break
    if value[:1] in ("'", '"'):
        end = value.find(value[0], 1)
        if end > 0:
            tail = value[end + 1 :].strip()
            if not tail or tail.startswith("#"):
                return value[1:end]
        return value
    return _strip_comment(value)


def _field_value(raw: str, nested: list[str]) -> str | list[str] | Unsupported:
    """A scalar as str, a one-line flow list or block list as list[str], else Unsupported."""
    try:
        return _field_shape(raw, nested)
    except _Escaped:
        return Unsupported("escape sequence in a double-quoted value")


def _field_shape(raw: str, nested: list[str]) -> str | list[str] | Unsupported:
    raw = raw.strip()
    if raw.startswith("#"):
        raw = ""
    if not raw:
        if not nested:
            return ""
        if all(line == "-" or line.startswith(("- ", "-\t")) for line in nested):
            return [item for item in (_unquote(line[1:]) for line in nested) if item]
        return Unsupported("nested mapping or other block value")
    if raw.startswith("["):
        body = _strip_comment(raw)
        if nested or not body.endswith("]"):
            return Unsupported("multi-line flow list")
        return [item for item in (_unquote(part) for part in _split_tools(body[1:-1])) if item]
    if raw.startswith("{"):
        return Unsupported("flow mapping")
    if _BLOCK_SCALAR.match(raw):
        return Unsupported("block scalar")
    if nested:
        return Unsupported("multi-line scalar")
    return _unquote(raw)


def parse_frontmatter(text: str) -> dict[str, str | list[str] | Unsupported] | None:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    raw: dict[str, tuple[str, list[str]]] = {}
    key: str | None = None
    for line in lines[1:]:
        if line.strip() == "---":
            return {k: _field_value(value, nested) for k, (value, nested) in raw.items()}
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        is_item = line.startswith("- ") or line.rstrip() == "-"
        if ":" in line and not line.startswith((" ", "\t")) and not is_item:
            name, _, value = line.partition(":")
            key = name.strip()
            raw[key] = (value.strip(), [])
        elif key is not None:
            raw[key][1].append(line.strip())
    return None


def agent_files(root: str) -> list[str]:
    """Agent definition paths under .claude/agents/ at any depth: relative, forward slashes."""
    base = os.path.join(root, ".claude", "agents")
    found = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for filename in filenames:
            if filename.endswith(".md"):
                found.append(os.path.relpath(os.path.join(dirpath, filename), base).replace(os.sep, "/"))
    return sorted(found)


def project_agent_names(root: str) -> frozenset[str]:
    """Frontmatter names of the agents defined under the project's .claude/agents/."""
    names: set[str] = set()
    for rel in agent_files(root):
        try:
            with open(os.path.join(root, ".claude", "agents", rel), encoding="utf-8") as fh:
                fields = parse_frontmatter(fh.read())
        except (OSError, ValueError):
            continue
        name = (fields or {}).get("name")
        if isinstance(name, str) and name:
            names.add(name)
    return frozenset(names)


def _read_settings(root: str, filename: str, problems: list[str], required: bool) -> dict:
    path = os.path.join(root, ".claude", filename)
    if not required and not os.path.isfile(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError("not an object")
        return data
    except (OSError, ValueError) as exc:
        problems.append(f".claude/{filename}: unreadable ({exc.__class__.__name__})")
        return {}


def _tool_name(entry: str) -> str:
    """A tool entry minus its argument: `Agent(sonnet-reviewer)` and `Write(src/**)` name Agent and Write."""
    return entry.split("(", 1)[0].strip()


def _split_tools(raw: str) -> list[str]:
    """Comma-separated entries, never splitting inside an argument list or a quoted entry.

    A quote opens only at the start of an entry, so an apostrophe inside an
    argument (`Bash(echo don't)`) cannot swallow the commas after it.
    """
    parts: list[str] = []
    depth = 0
    start = 0
    quote = ""
    for i, ch in enumerate(raw):
        if quote:
            if ch == quote:
                quote = ""
        elif ch in "\"'" and not depth and not raw[start:i].strip():
            quote = ch
        elif ch == "(":
            depth += 1
        elif ch == ")" and depth:
            depth -= 1
        elif ch == "," and not depth:
            parts.append(raw[start:i])
            start = i + 1
    parts.append(raw[start:])
    return parts


class _Malformed(ValueError):
    """A tools entry that is not `Name` or `Name(arguments)` with balanced parentheses."""


TOOL_ENTRY = re.compile(r"^[A-Za-z_][\w.-]*(\(.*\))?$", re.DOTALL)


def _tool_names(raw_tools: str | list[str]) -> set[str]:
    """Tool names in a frontmatter value: split outside quotes and parentheses, unquote, drop arguments.

    A list item is split again after unquoting, so `"Read, Agent"` as one
    quoted item still names Agent. Raises _Escaped for an escape sequence.
    """
    if isinstance(raw_tools, list):
        entries = raw_tools
    else:
        entries = [_unquote(part) for part in _split_tools(raw_tools)]
    names: set[str] = set()
    for entry in entries:
        for part in _split_tools(entry):
            part = part.strip()
            if not part:
                continue
            # Refuse what cannot be read for sure: an unbalanced argument list
            # could hide a later tool, and a non-identifier name is no tool.
            if part.count("(") != part.count(")") or not TOOL_ENTRY.match(part):
                raise _Malformed(part)
            names.add(_tool_name(part))
    return names


def check(root: str) -> list[str]:
    problems: list[str] = []
    agents_dir = os.path.join(root, ".claude", "agents")
    seen: set[str] = set()
    for rel in agent_files(root):
        stem = os.path.basename(rel)[:-3]
        where = f".claude/agents/{rel}"
        try:
            with open(os.path.join(agents_dir, rel), encoding="utf-8") as fh:
                fields = parse_frontmatter(fh.read())
        except (OSError, ValueError) as exc:
            problems.append(f"{where}: unreadable ({exc.__class__.__name__})")
            continue
        if fields is None:
            problems.append(f"{where}: no closed frontmatter block")
            continue

        def scalar(key: str) -> str | None:
            value = fields.get(key, "")
            if isinstance(value, Unsupported):
                problems.append(f"{where}: {key} uses an unsupported representation ({value.shape})")
                return None
            if isinstance(value, list):
                problems.append(f"{where}: {key} must be a single value, not a list")
                return None
            return value

        name = scalar("name")
        if name is None:
            continue
        if name != stem:
            problems.append(f"{where}: name '{name}' does not match the file name")
        route = ROUTED_AGENTS.get(name)
        if route is None:
            problems.append(f"{where}: '{name}' is not in ROUTED_AGENTS (scripts/agent_routing.py)")
            continue
        seen.add(name)
        model = scalar("model")
        if model is not None and model != route.model:
            problems.append(f"{where}: model '{model}' is not the pin '{route.model}'")
        effort = scalar("effort")
        if effort is not None and effort != route.effort:
            problems.append(f"{where}: effort '{effort}' is not the pin '{route.effort}'")
        if not fields.get("description"):
            problems.append(f"{where}: description is empty")
        raw_tools = fields.get("tools", "")
        if isinstance(raw_tools, Unsupported):
            problems.append(
                f"{where}: tools uses an unsupported representation ({raw_tools.shape}); "
                "use a comma-separated value, a one-line [flow, list], or a block list"
            )
            continue
        try:
            tools = _tool_names(raw_tools)
        except _Escaped:
            problems.append(f"{where}: tools uses an unsupported representation (escape sequence in a double-quoted value)")
            continue
        except _Malformed as exc:
            problems.append(f"{where}: tools entry '{exc}' is malformed (want Name or Name(arguments) with balanced parentheses)")
            continue
        if not tools:
            problems.append(f"{where}: tools must be an explicit list (an absent list inherits Agent)")
            continue
        for tool in sorted(tools & FORBIDDEN_TOOLS):
            problems.append(f"{where}: tool '{tool}' lets a delegate spawn agents")
        for tool in sorted(tools & WRITE_TOOLS):
            problems.append(f"{where}: read-only agent lists write tool '{tool}'")
        for tool in sorted(tools - READ_ONLY_TOOLS - FORBIDDEN_TOOLS - WRITE_TOOLS):
            problems.append(f"{where}: tool '{tool}' is not on the read-only allowlist {sorted(READ_ONLY_TOOLS)}")
        # Other frontmatter grants capabilities the tools list does not show
        # (memory adds Read, Write, and Edit; mcpServers and hooks add more).
        for key in sorted(set(fields) - AGENT_KEYS):
            problems.append(f"{where}: frontmatter key '{key}' is not allowed on a routed agent (allowed: {sorted(AGENT_KEYS)})")
    for name in sorted(set(ROUTED_AGENTS) - seen):
        problems.append(f".claude/agents/{name}.md: routed agent has no definition file")

    efforts = {route.effort for route in ROUTED_AGENTS.values()}
    models = {route.model for route in ROUTED_AGENTS.values()}
    settings = _read_settings(root, "settings.json", problems, required=True)
    for filename in SETTINGS_FILES:
        found = settings if filename == "settings.json" else _read_settings(root, filename, problems, required=False)
        if found.get("disableAllHooks") is True:
            problems.append(f".claude/{filename}: disableAllHooks is true, which switches off the routing hook and the Stop hook")
        env_block = found.get("env")
        if isinstance(env_block, dict):
            for var, _value in env_overrides(env_block, efforts, models):
                problems.append(
                    f".claude/{filename}: env sets {var}, which the routing hook denies "
                    "(it would silently change the pinned model or effort)"
                )
    wired = False
    for entry in (settings.get("hooks") or {}).get("PreToolUse") or []:
        if entry.get("matcher") != AGENT_TOOL_MATCHER:
            continue
        for hook in entry.get("hooks") or []:
            # Only a plain synchronous command hook can deny a call: `async`,
            # `asyncRewake`, or any other key may run it in the background.
            if (
                hook.get("type") == "command"
                and HOOK_COMMAND_MARK in str(hook.get("command", ""))
                and set(hook) <= HOOK_KEYS
            ):
                wired = True
    if not wired:
        problems.append(
            f".claude/settings.json: no PreToolUse hook with matcher '{AGENT_TOOL_MATCHER}' running agent_routing.py pre-agent"
        )

    record_path = os.path.join(root, RECORD)
    if not os.path.isfile(record_path):
        problems.append(f"{RECORD}: routing record is missing")
    else:
        with open(record_path, encoding="utf-8") as fh:
            record = fh.read()
        for name, route in ROUTED_AGENTS.items():
            if f"`{name}`" not in record:
                problems.append(f"{RECORD}: routed agent `{name}` is not recorded")
        if "Observed:" not in record:
            problems.append(f"{RECORD}: no `Observed:` line from a live `observe` run")
    return problems


def _transcripts(path: str) -> list[str]:
    if os.path.isfile(path):
        return [path]
    sub = os.path.join(path, "subagents")
    base = sub if os.path.isdir(sub) else path
    if not os.path.isdir(base):
        return []
    return sorted(os.path.join(base, n) for n in os.listdir(base) if n.startswith("agent-") and n.endswith(".jsonl"))


def observe(path: str) -> list[dict]:
    rows = []
    for jsonl in _transcripts(path):
        meta_path = jsonl[: -len(".jsonl")] + ".meta.json"
        agent_type = "?"
        if os.path.isfile(meta_path):
            try:
                with open(meta_path, encoding="utf-8") as fh:
                    agent_type = str(json.load(fh).get("agentType", "?"))
            except (OSError, ValueError):
                pass
        models: dict[str, int] = {}
        efforts: dict[str, int] = {}
        with open(jsonl, encoding="utf-8") as fh:
            for line in fh:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                message = entry.get("message")
                if entry.get("type") != "assistant" or not isinstance(message, dict):
                    continue
                model = message.get("model")
                if model:
                    models[model] = models.get(model, 0) + 1
                    effort = entry.get("perTurnEffort")
                    key = "none" if effort is None else str(effort)
                    efforts[key] = efforts.get(key, 0) + 1
        rows.append({"transcript": os.path.basename(jsonl), "agent_type": agent_type, "models": models, "efforts": efforts})
    return rows


def _fmt_counts(counts: dict[str, int]) -> str:
    return ", ".join(f"{k} x{v}" for k, v in sorted(counts.items())) or "none"


def _self_test() -> int:
    failures: list[str] = []
    ran = [0]

    def expect(label: str, cond: bool) -> None:
        ran[0] += 1
        if not cond:
            failures.append(label)

    expect("routed, no override allowed", decide({"subagent_type": "sonnet-verifier"}) is None)
    expect("a removed implementer file is denied as unrouted", decide({"subagent_type": "sonnet-implementer"}, None, frozenset({"sonnet-implementer"})) is not None)
    expect("routed, matching override allowed", decide({"subagent_type": "sonnet-researcher", "model": "sonnet"}) is None)
    expect("routed, haiku override denied", decide({"subagent_type": "sonnet-verifier", "model": "haiku"}) is not None)
    expect("routed, opus override denied", decide({"subagent_type": "sonnet-reviewer", "model": "opus"}) is not None)
    expect("general-purpose denied", decide({"subagent_type": "general-purpose"}) is not None)
    expect("missing type denied", decide({}) is not None)
    expect("Explore denied", decide({"subagent_type": "Explore"}) is not None)
    expect("claude catch-all denied", decide({"subagent_type": "claude"}) is not None)
    expect("Explore on sonnet denied", decide({"subagent_type": "Explore", "model": "sonnet"}) is not None)
    expect("Plan with opus escalation allowed", decide({"subagent_type": "Plan", "model": "opus"}) is None)
    expect("fork allowed", decide({"subagent_type": "fork"}) is None)
    expect("claude-code-guide denied", decide({"subagent_type": "claude-code-guide"}) is not None)
    expect("other type allowed", decide({"subagent_type": "statusline-setup"}) is None)

    # Session env overrides (hermetic: the env is always passed, never os.environ).
    verifier = {"subagent_type": "sonnet-verifier"}
    reason = decide(verifier, {EFFORT_ENV: "low"})
    expect("effort override denied, names the variable", reason is not None and EFFORT_ENV in reason and "silently change" in reason)
    expect("effort override matching the pin allowed", decide(verifier, {EFFORT_ENV: "high"}) is None)
    expect("effort override matching the pin is case-insensitive", decide(verifier, {EFFORT_ENV: " HIGH "}) is None)
    expect("effort override empty allowed", decide(verifier, {EFFORT_ENV: ""}) is None)
    expect("effort override on a fork untouched", decide({"subagent_type": "fork"}, {EFFORT_ENV: "low"}) is None)
    for var in MODEL_ENVS:
        reason = decide(verifier, {var: "claude-haiku-4-5", FORCE_ENV: "1"})
        expect(f"{var} denied, names the variable", reason is not None and var in reason and "silently change" in reason)
        expect(f"{var} empty allowed", decide(verifier, {var: "", FORCE_ENV: "1"}) is None)
        expect(f"{var} on a fork untouched", decide({"subagent_type": "fork"}, {var: "x", FORCE_ENV: "1"}) is None)
    expect("subagent model env at the pin allowed", decide(verifier, {MODEL_ENVS[1]: "sonnet", FORCE_ENV: "1"}) is None)
    expect("subagent model env unforced is a fallback below frontmatter", decide(verifier, {MODEL_ENVS[1]: "haiku"}) is None)
    expect("subagent model env with a falsy force allowed", decide(verifier, {MODEL_ENVS[1]: "haiku", FORCE_ENV: "false"}) is None)
    expect("sonnet alias env denied without force", decide(verifier, {ALIAS_ENV: "claude-sonnet-4-5"}) is not None)
    expect("sonnet alias env denied even when it says sonnet", decide(verifier, {ALIAS_ENV: "sonnet"}) is not None)
    expect("unrelated env allowed", decide(verifier, {"PATH": "x", "CLAUDE_PROJECT_DIR": "y"}) is None)

    # Unrouted project agents (any depth) are denied; routed ones and unknown types are not.
    expect("unrouted project agent denied", decide({"subagent_type": "haiku-helper"}, None, frozenset({"haiku-helper"})) is not None)
    expect(
        "unrouted project agent denied despite opus",
        decide({"subagent_type": "haiku-helper", "model": "opus"}, None, frozenset({"haiku-helper"})) is not None,
    )
    expect("routed agent in project set allowed", decide(verifier, None, frozenset(ROUTED_AGENTS)) is None)
    expect("type absent from project set allowed", decide({"subagent_type": "haiku-helper"}, None, frozenset({"other"})) is None)

    with tempfile.TemporaryDirectory() as empty:
        out = run_pre_agent(json.dumps({"tool_name": "Agent", "tool_input": {"subagent_type": "general-purpose"}}), {}, empty)
        expect("deny payload shape", json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny" if out else False)
        expect("allow payload empty", run_pre_agent(json.dumps({"tool_input": verifier}), {}, empty) == "")
        expect("bad payload fails open", run_pre_agent("{not json", {}, empty) == "")
        expect("non-dict input fails open", run_pre_agent(json.dumps({"tool_input": "x"}), {}, empty) == "")
        out = run_pre_agent(json.dumps({"tool_input": verifier}), {EFFORT_ENV: "low"}, empty)
        expect("hook denies effort override", json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny" if out else False)
        expect("hook allows once the override is gone", run_pre_agent(json.dumps({"tool_input": verifier}), {EFFORT_ENV: ""}, empty) == "")
        expect("missing root fails open", run_pre_agent(json.dumps({"tool_input": {"subagent_type": "fork"}}), {}, os.path.join(empty, "nope")) == "")

    expect("frontmatter parse", parse_frontmatter("---\nname: a\nmodel: sonnet\n---\nbody") == {"name": "a", "model": "sonnet"})
    expect("unclosed frontmatter", parse_frontmatter("---\nname: a\n") is None)
    expect(
        "frontmatter quoted values",
        parse_frontmatter("---\nmodel: \"sonnet\"\neffort: 'high'\nname: a # note\n---\n") == {"model": "sonnet", "effort": "high", "name": "a"},
    )
    expect("frontmatter flow list", parse_frontmatter("---\ntools: [Read, \"Grep\", 'Glob']\n---\n") == {"tools": ["Read", "Grep", "Glob"]})
    expect("frontmatter block list", parse_frontmatter("---\ntools:\n  - Read\n  - \"Grep\"\nmodel: sonnet\n---\n") == {"tools": ["Read", "Grep"], "model": "sonnet"})
    expect("frontmatter flush block list", parse_frontmatter("---\ntools:\n- Read\n- Grep\n---\n") == {"tools": ["Read", "Grep"]})
    expect(
        "frontmatter mapping unsupported",
        parse_frontmatter("---\ntools:\n  Read: true\n---\n") == {"tools": Unsupported("nested mapping or other block value")},
    )
    expect(
        "frontmatter multi-line flow list unsupported",
        parse_frontmatter("---\ntools: [Read,\n  Grep]\n---\n") == {"tools": Unsupported("multi-line flow list")},
    )
    expect(
        "frontmatter block scalar unsupported, never read as its indicator",
        parse_frontmatter("---\ndescription: >\n  one\n  two\ntools: >-\n  Read, Write\n---\n")
        == {"description": Unsupported("block scalar"), "tools": Unsupported("block scalar")},
    )
    expect(
        "frontmatter escaped double-quoted value unsupported",
        parse_frontmatter('---\ntools: [Read, "Wr\\u0069te"]\nmodel: "s\\x6fnnet"\n---\n')
        == {"tools": Unsupported("escape sequence in a double-quoted value"), "model": Unsupported("escape sequence in a double-quoted value")},
    )
    expect("frontmatter disallowedTools never errors", isinstance(parse_frontmatter("---\ndisallowedTools:\n  Bash: no\n---\n"), dict))

    def build(
        root: str,
        agents: dict[str, str],
        hook: bool = True,
        record: str | None = None,
        settings_extra: dict | None = None,
        local: dict | None = None,
    ) -> None:
        os.makedirs(os.path.join(root, ".claude", "agents"), exist_ok=True)
        os.makedirs(os.path.join(root, "docs"), exist_ok=True)
        for name, body in agents.items():
            path = os.path.join(root, ".claude", "agents", f"{name}.md")
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(body)
        hooks = {}
        if hook:
            command = 'python3 "$CLAUDE_PROJECT_DIR/scripts/agent_routing.py" pre-agent'
            hooks = {"PreToolUse": [{"matcher": AGENT_TOOL_MATCHER, "hooks": [{"type": "command", "command": command}]}]}
        with open(os.path.join(root, ".claude", "settings.json"), "w", encoding="utf-8") as fh:
            json.dump({"hooks": hooks, **(settings_extra or {})}, fh)
        if local is not None:
            with open(os.path.join(root, ".claude", "settings.local.json"), "w", encoding="utf-8") as fh:
                json.dump(local, fh)
        if record is None:
            record = "Observed: x\n" + "\n".join(f"`{n}`" for n in ROUTED_AGENTS)
        with open(os.path.join(root, RECORD), "w", encoding="utf-8") as fh:
            fh.write(record)

    def agent(name: str, model: str = "sonnet", effort: str = "high", tools: str | None = None) -> str:
        if tools is None:
            tools = "Read, Grep"
        return f"---\nname: {name}\ndescription: d\nmodel: {model}\neffort: {effort}\ntools: {tools}\n---\nbody\n"

    good = {n: agent(n) for n in ROUTED_AGENTS}
    with tempfile.TemporaryDirectory() as root:
        build(root, good)
        expect("green fixture passes", check(root) == [])
    green_cases = [
        ("read-only agent with a scoped read tool", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Read(src/**), Grep")}, {}),
        ("quoted values", {**good, "sonnet-verifier": agent("sonnet-verifier", model='"sonnet"', effort="'high'")}, {}),
        ("flow list tools", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='[Read, "Grep", \'Glob\']')}, {}),
        ("block list tools", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="\n  - Read\n  - Grep")}, {}),
        ("effort env at the pin", good, {"settings_extra": {"env": {EFFORT_ENV: "high", "OTHER": "x"}}}),
        ("subagent model env at the pin", good, {"settings_extra": {"env": {MODEL_ENVS[1]: "sonnet", FORCE_ENV: "1"}}}),
        ("subagent model env unforced", good, {"settings_extra": {"env": {MODEL_ENVS[1]: "haiku"}}}),
        ("backslash only in a comment", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='"Read, Grep" # C:\\review\\notes')}, {}),
        ("block scalar description", {**good, "sonnet-verifier": agent("sonnet-verifier").replace("description: d", "description: >\n  folded")}, {}),
        ("hooks not disabled", good, {"settings_extra": {"disableAllHooks": False}, "local": {"disableAllHooks": False}}),
    ]
    for label, agents, kwargs in green_cases:
        with tempfile.TemporaryDirectory() as root:
            build(root, agents, **kwargs)
            expect(f"green fixture passes: {label}", check(root) == [])
    nested_unrouted = agent("sonnet-verifier").replace("sonnet-verifier", "haiku-helper")
    cases = [
        ("model drift", {**good, "sonnet-verifier": agent("sonnet-verifier", model="haiku")}, {}, "model 'haiku'"),
        ("effort drift", {**good, "sonnet-researcher": agent("sonnet-researcher", effort="medium")}, {}, "effort 'medium'"),
        ("read-only writes", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Read, Edit")}, {}, "write tool 'Edit'"),
        ("nested agents", {**good, "sonnet-researcher": agent("sonnet-researcher", tools="Read, Grep, Agent")}, {}, "tool 'Agent'"),
        ("a scoped write tool is still a write tool", {**good, "sonnet-researcher": agent("sonnet-researcher", tools="Read, Write(src/**), Bash(git status:*)")}, {}, "write tool 'Write'"),
        ("a quoted scoped write holding a comma is still a write tool", {**good, "sonnet-verifier": agent("sonnet-verifier", tools='[Read, "Write(src/**, tests/**)", Bash]')}, {}, "write tool 'Write'"),
        # Tool entries may carry arguments; the name before `(` is what counts.
        ("nested agents with an argument", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Read, Agent(sonnet-reviewer)")}, {}, "tool 'Agent'"),
        ("read-only agent with a scoped write", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Read, Write(src/**)")}, {}, "write tool 'Write'"),
        ("scoped write after an argument comma", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Read, Edit(a, b), Grep")}, {}, "write tool 'Edit'"),
        ("flow list tool with an argument", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="[Read, 'Task(x)']")}, {}, "tool 'Task'"),
        # A quoted entry whose argument list holds a comma stays one entry; the name before `(` still counts.
        (
            "quoted flow list Agent with a comma in its arguments",
            {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='[Read, "Agent(sonnet-researcher, sonnet-verifier)"]')},
            {},
            "tool 'Agent'",
        ),
        ("quoted comma scalar Agent with a comma in its arguments", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='Read, "Agent(a, b)"')}, {}, "tool 'Agent'"),
        ("quoted flow list scoped write after a comma", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="[Read, 'Write(a, b)']")}, {}, "write tool 'Write'"),
        ("one quoted item hiding a second tool", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='["Read, Agent"]')}, {}, "tool 'Agent'"),
        ("agent after an argument with an apostrophe", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="Bash(echo don't), Agent")}, {}, "tool 'Agent'"),
        ("implicit tools", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="")}, {}, "explicit list"),
        ("unrouted agent", {**good, "haiku-helper": nested_unrouted}, {}, "not in ROUTED_AGENTS"),
        ("missing agent", {n: b for n, b in good.items() if n != "sonnet-researcher"}, {}, "no definition file"),
        ("hook unwired", good, {"hook": False}, "no PreToolUse hook"),
        ("record gap", good, {"record": "Observed: x\n`sonnet-researcher`"}, "`sonnet-verifier` is not recorded"),
        # Frontmatter shapes: quoted values and lists are read, the rest is refused.
        ("quoted model drift", {**good, "sonnet-verifier": agent("sonnet-verifier", model='"haiku"')}, {}, "model 'haiku'"),
        ("quoted effort drift", {**good, "sonnet-verifier": agent("sonnet-verifier", effort="'low'")}, {}, "effort 'low'"),
        ("flow list forbidden tool", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="[Read, 'Agent']")}, {}, "tool 'Agent'"),
        ("flow list write tool", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="[Read, Write]")}, {}, "write tool 'Write'"),
        ("block list write tool", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools="\n  - Read\n  - Edit")}, {}, "write tool 'Edit'"),
        ("block list forbidden tool", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="\n  - Read\n  - Task")}, {}, "tool 'Task'"),
        ("mapping tools", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="\n  Read: true")}, {}, "tools uses an unsupported representation"),
        ("multi-line flow tools", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="[Read,\n  Grep]")}, {}, "tools uses an unsupported representation"),
        ("folded tools hide a write tool", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools=">-\n  Read, Write")}, {}, "tools uses an unsupported representation (block scalar)"),
        ("escaped tool name", {**good, "sonnet-reviewer": agent("sonnet-reviewer", tools='[Read, "Wr\\u0069te"]')}, {}, "tools uses an unsupported representation (escape sequence"),
        ("folded model", {**good, "sonnet-verifier": agent("sonnet-verifier", model="|\n  haiku")}, {}, "model uses an unsupported representation (block scalar)"),
        ("empty flow tools", {**good, "sonnet-verifier": agent("sonnet-verifier", tools="[]")}, {}, "explicit list"),
        # Recursive discovery: Claude loads definitions from nested directories.
        ("nested unrouted agent", {**good, "sub/deep/haiku-helper": nested_unrouted}, {}, ".claude/agents/sub/deep/haiku-helper.md: 'haiku-helper' is not in ROUTED_AGENTS"),
        (
            "nested routed agent drift",
            {**good, "sub/sonnet-reviewer": agent("sonnet-reviewer", model="haiku")},
            {},
            ".claude/agents/sub/sonnet-reviewer.md: model 'haiku'",
        ),
        # Env overrides pinned in project settings.
        ("settings effort env", good, {"settings_extra": {"env": {EFFORT_ENV: "low"}}}, f"settings.json: env sets {EFFORT_ENV}"),
        ("settings sonnet-model env", good, {"settings_extra": {"env": {MODEL_ENVS[0]: "claude-haiku-4-5"}}}, f"env sets {MODEL_ENVS[0]}"),
        ("settings subagent-model env", good, {"settings_extra": {"env": {MODEL_ENVS[1]: "opus", FORCE_ENV: "1"}}}, f"env sets {MODEL_ENVS[1]}"),
        ("local effort env", good, {"local": {"env": {EFFORT_ENV: "max"}}}, f"settings.local.json: env sets {EFFORT_ENV}"),
        ("local model env", good, {"local": {"env": {MODEL_ENVS[1]: "haiku", FORCE_ENV: "true"}}}, f"settings.local.json: env sets {MODEL_ENVS[1]}"),
        # Disabled hooks keep the wiring looking present.
        ("hooks disabled", good, {"settings_extra": {"disableAllHooks": True}}, "settings.json: disableAllHooks is true"),
        ("hooks disabled locally", good, {"local": {"disableAllHooks": True}}, "settings.local.json: disableAllHooks is true"),
    ]
    for label, agents, kwargs, needle in cases:
        with tempfile.TemporaryDirectory() as root:
            build(root, agents, **kwargs)
            problems = check(root)
            expect(f"red fixture fires: {label}", any(needle in p for p in problems))

    # Final review: capabilities granted outside the tools list, and an async hook that cannot deny.
    capability_cases = [
        ("memory grants Read, Write, and Edit", agent("sonnet-reviewer").replace("tools: Read, Grep", "tools: Read, Grep\nmemory: project"), "frontmatter key 'memory'"),
        ("mcpServers adds tools", agent("sonnet-reviewer").replace("tools: Read, Grep", "tools: Read, Grep\nmcpServers: [fs]"), "frontmatter key 'mcpServers'"),
        ("an MCP write tool is off the allowlist", agent("sonnet-reviewer", tools="Read, mcp__filesystem__write_file"), "tool 'mcp__filesystem__write_file' is not on the read-only allowlist"),
    ]
    for label, body, needle in capability_cases:
        with tempfile.TemporaryDirectory() as root:
            build(root, {**good, "sonnet-reviewer": body})
            expect(f"red fixture fires: {label}", any(needle in p for p in check(root)))
    with tempfile.TemporaryDirectory() as root:
        build(root, {**good, "sonnet-reviewer": agent("sonnet-reviewer").replace("tools: Read, Grep", "tools: Read, Grep\ndisallowedTools: Bash")})
        expect("green fixture passes: disallowedTools only narrows", check(root) == [])
    with tempfile.TemporaryDirectory() as root:
        build(root, good)
        path = os.path.join(root, ".claude", "settings.json")
        with open(path, encoding="utf-8") as fh:
            settings = json.load(fh)
        for extra in ({"async": True}, {"asyncRewake": True}, {"async": False, "asyncRewake": True}, {"background": 1}):
            hook = {**settings["hooks"]["PreToolUse"][0]["hooks"][0], **extra}
            with open(path, "w", encoding="utf-8") as fh:
                json.dump({**settings, "hooks": {"PreToolUse": [{"matcher": AGENT_TOOL_MATCHER, "hooks": [hook]}]}}, fh)
            expect(f"red fixture fires: a routing hook with {sorted(extra)} cannot be trusted to deny", any("no PreToolUse hook" in p for p in check(root)))
        timed = {**settings["hooks"]["PreToolUse"][0]["hooks"][0], "timeout": 15}
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({**settings, "hooks": {"PreToolUse": [{"matcher": AGENT_TOOL_MATCHER, "hooks": [timed]}]}}, fh)
        expect("green fixture passes: a timeout keeps the hook synchronous", check(root) == [])

    # Hook scan of the project's agents (hermetic: the root is passed in).
    with tempfile.TemporaryDirectory() as root:
        build(root, {**good, "sub/deep/haiku-helper": nested_unrouted})
        names = project_agent_names(root)
        expect("project scan finds nested agents", names == frozenset(ROUTED_AGENTS) | {"haiku-helper"})
        out = run_pre_agent(json.dumps({"tool_input": {"subagent_type": "haiku-helper"}}), {}, root)
        expect("hook denies a nested unrouted agent", json.loads(out)["hookSpecificOutput"]["permissionDecision"] == "deny" if out else False)
        expect("hook still allows a routed agent", run_pre_agent(json.dumps({"tool_input": verifier}), {}, root) == "")
        out = run_pre_agent(json.dumps({"tool_input": {"subagent_type": "haiku-helper"}}), {"CLAUDE_PROJECT_DIR": root})
        expect("hook finds the root from CLAUDE_PROJECT_DIR", bool(out) and "haiku-helper" in out)

    with tempfile.TemporaryDirectory() as root:
        sub = os.path.join(root, "subagents")
        os.makedirs(sub)
        with open(os.path.join(sub, "agent-x.meta.json"), "w", encoding="utf-8") as fh:
            json.dump({"agentType": "sonnet-verifier"}, fh)
        with open(os.path.join(sub, "agent-x.jsonl"), "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "user", "message": {"role": "user"}}) + "\n")
            fh.write(json.dumps({"type": "assistant", "perTurnEffort": "high", "message": {"model": "claude-sonnet-5-5"}}) + "\n")
            fh.write("not json\n")
        rows = observe(root)
        expect(
            "observe reads model and effort",
            rows == [{"transcript": "agent-x.jsonl", "agent_type": "sonnet-verifier", "models": {"claude-sonnet-5-5": 1}, "efforts": {"high": 1}}],
        )

    total = ran[0]
    if failures:
        for label in failures:
            print(f"FAIL {label}")
        print(f"agent_routing self-test: {total - len(failures)}/{total} passed")
        return 1
    print(f"agent_routing self-test: {total}/{total} passed")
    return 0


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__.strip().splitlines()[0])
        print(
            "usage: agent_routing.py check [--root DIR] | pre-agent | observe <path> | self-test"
        )
        return 2
    command, rest = argv[0], argv[1:]
    if command == "pre-agent":
        out = run_pre_agent(sys.stdin.read())
        if out:
            print(out)
        return 0
    if command == "self-test":
        return _self_test()
    if command == "check":
        root = rest[1] if len(rest) == 2 and rest[0] == "--root" else default_root()
        problems = check(root)
        for problem in problems:
            print(f"FATAL {problem}")
        print(f"agent_routing check: {len(ROUTED_AGENTS)} routed agents, {len(problems)} problems")
        return 1 if problems else 0
    if command == "observe" and len(rest) == 1:
        rows = observe(rest[0])
        if not rows:
            print(f"observe: no subagent transcripts under {rest[0]}")
            return 1
        for row in rows:
            print(f"{row['agent_type']}: model {_fmt_counts(row['models'])}; effort {_fmt_counts(row['efforts'])} ({row['transcript']})")
        return 0
    print(f"unknown command: {' '.join(argv)}")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
