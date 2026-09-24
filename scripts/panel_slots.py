"""Slot resolution for the review panel (D00 T04 §15).

`.conclave/panel.toml` binds review slots to (model, effort, timeout).
`review_prompt.py run --slot` resolves producer argv here; the validator
governs the closed sets from here so pins and checks cannot drift apart;
`probe_runner.py` checks the TOML's codex templates from here so the
checked-in control can never disagree with the wiring.

Schema note (governance, not convenience): PANEL_MODELS and
PANEL_EFFORTS are closed. A new producer or level arrives with probes
plus review, never by TOML edit alone. PANEL_SLOTS is exact: a slot is
regime (the outage-matrix prose names it), so a slot without matrix
prose is ungoverned and fails. D00 T04 §25 shrinks the regime to five
sol primaries plus one Grok `fallback`: every slot pins its own effort,
so EFFORT_PARITY is empty and no `inherit` exists.

`grok-latest` is the one alias in PANEL_MODELS (operator direction
2026-09-23: the fallback always runs the newest Grok). It resolves at
argv time to the highest `grok-<major>.<minor>` id in the Grok CLI
model cache, so a new Grok release is picked up without an edit; the
runner prints the resolved id so the record names the model that ran.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tomllib

GROK_LATEST = "grok-latest"
# gpt-6-sol stays in the set so the primary can be re-pinned back to it
# by TOML edit alone (operator direction 2026-09-24).
PANEL_MODELS = ("gpt-6-astra", "gpt-6-sol", GROK_LATEST)
PANEL_EFFORTS = ("medium", "high", "xhigh")
PANEL_SLOTS = (
    "bulk",
    "signoff",
    "depth",
    "plan-primary",
    "arch-primary",
    "fallback",
)
# One fallback slot on a different provider replaces the per-role
# ladder (D00 T04 §25), so no slot repeats another's effort.
EFFORT_PARITY: tuple[tuple[str, str], ...] = ()
# Grok ids in the CLI cache: `grok-4.7`; suffixed variants such as
# `grok-4.7-build-fast` never win resolution.
_GROK_ID_RE = re.compile(r"grok-(\d+)\.(\d+)")


# Record words per runner family: panel headings read `<label> panel`,
# plan-review rungs read `<rung>` (D00 T04 §25). Families, not models:
# a re-pin inside a family never touches these.
FAMILY_LABELS = {"codex": "GPT", "grok": "Grok", "claude": "Claude"}
FAMILY_RUNGS = {"codex": "gpt rung", "grok": "grok rung", "claude": "claude rung"}
# The writer family when the TOML names none: the defaults only guard a
# fixture root without a TOML, the live TOML always states it.
DEFAULT_FAMILIES = {"primary": "codex", "fallback": "grok", "writer": "claude"}


class PanelSlotsError(ValueError):
    """A naming diagnostic for panel-slot resolution failures."""


def toml_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", ".conclave", "panel.toml")


def grok_cache_path() -> str:
    """The Grok CLI model cache; GROK_MODELS_CACHE overrides it for fixtures."""
    override = os.environ.get("GROK_MODELS_CACHE")
    if override:
        return override
    return os.path.join(os.path.expanduser("~"), ".grok", "models_cache.json")


def resolve_grok_latest(path: str | None = None) -> str:
    """The newest `grok-<major>.<minor>` id in the cache. Raises PanelSlotsError naming why not."""
    src = path or grok_cache_path()
    try:
        with open(src, encoding="utf-8") as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        raise PanelSlotsError(f"grok model cache {src} does not exist (run the Grok CLI once to fill it)")
    except (OSError, ValueError) as exc:
        raise PanelSlotsError(f"grok model cache {src} does not parse: {exc}")
    models = doc.get("models", doc) if isinstance(doc, dict) else None
    if not isinstance(models, dict):
        raise PanelSlotsError(f"grok model cache {src} carries no model table")
    best: tuple[int, int] | None = None
    for key in models:
        m = _GROK_ID_RE.fullmatch(str(key))
        if m and (best is None or (int(m.group(1)), int(m.group(2))) > best):
            best = (int(m.group(1)), int(m.group(2)))
    if best is None:
        raise PanelSlotsError(f"grok model cache {src} names no grok-<major>.<minor> model")
    return f"grok-{best[0]}.{best[1]}"


def grok_binary() -> str:
    """`grok` from PATH, else the CLI's default install, else the bare name."""
    found = shutil.which("grok")
    if found:
        return found
    default = os.path.join(os.path.expanduser("~"), ".grok", "bin", "grok.exe")
    return default if os.path.isfile(default) else "grok"


def family_for_model(model: str) -> str:
    if model.startswith("gpt-"):
        return "codex"
    if model.startswith("grok-"):
        return "grok"
    if model.startswith("claude-"):
        return "claude"
    raise PanelSlotsError(f"panel slot model {model!r} names no known runner family")


def load_slots(path: str | None = None) -> dict[str, dict]:
    """Load and validate the slot table. Raises PanelSlotsError naming why not."""
    src = path or toml_path()
    try:
        with open(src, "rb") as fh:
            doc = tomllib.load(fh)
    except FileNotFoundError:
        raise PanelSlotsError(f"panel slots file {src} does not exist")
    except tomllib.TOMLDecodeError as exc:
        raise PanelSlotsError(f"panel slots file {src} does not parse: {exc}")
    tables = doc.get("slot", {})
    if not isinstance(tables, dict):
        raise PanelSlotsError("panel slots file carries no [slot.*] tables")
    missing = [name for name in PANEL_SLOTS if name not in tables]
    if missing:
        raise PanelSlotsError(f"panel slots file is missing slots: {', '.join(missing)}")
    extra = [name for name in tables if name not in PANEL_SLOTS]
    if extra:
        raise PanelSlotsError(f"panel slots file carries ungoverned slots: {', '.join(sorted(extra))}")
    slots: dict[str, dict] = {}
    for name in PANEL_SLOTS:
        entry = tables[name]
        if not isinstance(entry, dict):
            raise PanelSlotsError(f"panel slot {name!r} is not a table")
        model = entry.get("model")
        if model not in PANEL_MODELS:
            raise PanelSlotsError(f"panel slot {name!r} model {model!r} is outside {', '.join(PANEL_MODELS)}")
        effort = entry.get("effort")
        if effort not in PANEL_EFFORTS:
            raise PanelSlotsError(f"panel slot {name!r} effort {effort!r} is outside {', '.join(PANEL_EFFORTS)}")
        timeout = entry.get("timeout")
        if type(timeout) is not int or timeout <= 0:
            raise PanelSlotsError(f"panel slot {name!r} timeout {timeout!r} is not a positive integer")
        slots[name] = {
            "model": model,
            "effort": effort,
            "timeout": timeout,
            "family": family_for_model(model),
        }
    for follower, leader in EFFORT_PARITY:
        if slots[follower]["effort"] != slots[leader]["effort"]:
            raise PanelSlotsError(
                f"panel slot {follower!r} effort {slots[follower]['effort']!r} does not repeat "
                f"slot {leader!r} effort {slots[leader]['effort']!r}"
            )
    return slots


PROMPT_TOKEN = "{prompt}"


def panel_families(path: str | None = None) -> dict[str, str]:
    """{primary, fallback, writer} families from the TOML (D00 T04 §25).

    primary is the `signoff` slot's family, fallback the `fallback`
    slot's, writer the `[panel] writer` key. A missing or invalid TOML
    reads the defaults so fixture roots stay deterministic; the
    `panel-slots` validator leg reports a broken live TOML on its own.
    """
    src = path or toml_path()
    try:
        slots = load_slots(src)
        with open(src, "rb") as fh:
            writer = tomllib.load(fh).get("panel", {}).get("writer")
    except (PanelSlotsError, OSError, tomllib.TOMLDecodeError):
        return dict(DEFAULT_FAMILIES)
    return {
        "primary": slots["signoff"]["family"],
        "fallback": slots["fallback"]["family"],
        "writer": writer if isinstance(writer, str) and writer else DEFAULT_FAMILIES["writer"],
    }


def argv_for_slot(
    slot: str,
    slots: dict[str, dict] | None = None,
    prompt_path: str | None = None,
    grok_cache: str | None = None,
) -> list[str]:
    """Producer argv for a slot. Raises PanelSlotsError naming why not.

    Grok reads no prompt from stdin headless (probed 2026-09-23), so its
    argv carries `--prompt-file`: the given path, else PROMPT_TOKEN for
    the runner to substitute.
    """
    table = slots if slots is not None else load_slots()
    if slot not in table:
        raise PanelSlotsError(f"panel slot {slot!r} is unknown (known: {', '.join(sorted(table))})")
    entry = table[slot]
    model, effort = entry["model"], entry["effort"]
    if entry["family"] == "codex":
        return ["codex", "exec", "-m", model, "-c", f"model_reasoning_effort={effort}", "-s", "read-only", "-"]
    if entry["family"] == "grok":
        if model == GROK_LATEST:
            model = resolve_grok_latest(grok_cache)
        return [
            "grok", "-m", model, "--reasoning-effort", effort, "--output-format", "plain",
            "--permission-mode", "plan", "--no-subagents", "--disable-web-search", "--tools", "Read",
            "--prompt-file", prompt_path or PROMPT_TOKEN,
        ]
    return ["claude", "-p", "--model", model, "--effort", effort, "--allowedTools", "Read"]


def codex_templates(slots: dict[str, dict] | None = None) -> list[tuple[str, list[str]]]:
    """(slot, argv) for every codex slot, sorted by slot for determinism."""
    table = slots if slots is not None else load_slots()
    return [(name, argv_for_slot(name, table)) for name in sorted(table) if table[name]["family"] == "codex"]
