"""Slot resolution for the review panel (D00 T04 §15).

`.conclave/panel.toml` binds review slots to (model, effort, timeout).
`review_prompt.py run --slot` resolves producer argv here; the validator
governs the closed sets from here so pins and checks cannot drift apart;
`probe_runner.py` checks the TOML's codex templates from here so the
checked-in control can never disagree with the wiring.

Schema note (governance, not convenience): PANEL_MODELS and
PANEL_EFFORTS are closed. A new producer or level arrives with probes
plus review, never by TOML edit alone. PANEL_SLOTS is exact: a slot is
regime (the outage-matrix prose names it), so an 11th slot without
matrix prose is ungoverned and fails. Same-family failovers repeat
their slot effort by rule (EFFORT_PARITY): no `inherit` exists.
"""

from __future__ import annotations

import os
import tomllib

PANEL_MODELS = ("gpt-6-sol", "gpt-5.6-terra", "claude-opus-5-5")
PANEL_EFFORTS = ("medium", "high", "xhigh")
PANEL_SLOTS = (
    "bulk",
    "signoff",
    "depth",
    "bulk-fallback",
    "signoff-fallback",
    "cross-fill",
    "plan-primary",
    "plan-fallback",
    "arch-primary",
    "arch-fallback",
)
# cross-fill is cross-family and fills any round, sign-off included, so
# it pins its own effort (high) instead of repeating bulk (D00 T04 §23).
EFFORT_PARITY = (("bulk-fallback", "bulk"),)


class PanelSlotsError(ValueError):
    """A naming diagnostic for panel-slot resolution failures."""


def toml_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(here, "..", ".conclave", "panel.toml")


def family_for_model(model: str) -> str:
    if model.startswith("gpt-"):
        return "codex"
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


def argv_for_slot(slot: str, slots: dict[str, dict] | None = None) -> list[str]:
    """Producer argv for a slot. Raises PanelSlotsError naming why not."""
    table = slots if slots is not None else load_slots()
    if slot not in table:
        raise PanelSlotsError(f"panel slot {slot!r} is unknown (known: {', '.join(sorted(table))})")
    entry = table[slot]
    model, effort = entry["model"], entry["effort"]
    if entry["family"] == "codex":
        return ["codex", "exec", "-m", model, "-c", f"model_reasoning_effort={effort}", "-s", "read-only", "-"]
    return ["claude", "-p", "--model", model, "--effort", effort, "--allowedTools", "Read"]


def codex_templates(slots: dict[str, dict] | None = None) -> list[tuple[str, list[str]]]:
    """(slot, argv) for every codex slot, sorted by slot for determinism."""
    table = slots if slots is not None else load_slots()
    return [(name, argv_for_slot(name, table)) for name in sorted(table) if table[name]["family"] == "codex"]
