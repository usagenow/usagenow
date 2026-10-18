#!/usr/bin/env python3
"""Regenerates Shared/Resources/ModelPrices.json from published model prices.

UsageNow shows an estimate of what local token activity would have cost at
list prices. The estimate is only as honest as its table, so the table is
generated from a maintained source plus reviewed vendor overrides, and it
records where and when it came from.

Source: LiteLLM's model_prices_and_context_window.json (MIT), which tracks
Anthropic, OpenAI and Google list prices including prompt-cache rates. Spot
checks against the vendors' own pricing pages are part of reviewing a
regenerated table. Reviewed vendor overrides, including dated price changes,
live in scripts/model-price-overrides.json and take precedence over the feed.

Usage: scripts/update-model-prices.py [--source URL]
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import subprocess
from decimal import Decimal

SOURCE = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

# Families UsageNow can actually see in local sessions: Claude Code, Codex,
# Gemini CLI, Antigravity and OpenCode. Keys with a provider prefix
# ("vertex_ai/…") are other platforms' prices and are excluded, except the
# prefixes below, which are each vendor's own API.
FAMILIES = ("claude-", "gpt-6", "gpt-5", "gpt-4.1", "o3", "o4-", "gemini-", "codex-")

# Models OpenCode users commonly run, priced by the vendor's own API. Stored
# without the prefix, the way OpenCode records the model.
OWN_API_PREFIXES = ("deepseek/", "moonshot/", "xai/", "mistral/")

FIELDS = {
    "input": "input_cost_per_token",
    "output": "output_cost_per_token",
    "cacheWrite": "cache_creation_input_token_cost",
    "cacheRead": "cache_read_input_token_cost",
}


def per_million(cost_per_token: float) -> str:
    """Formats a per-token cost as an exact per-million-token decimal string."""
    value = (Decimal(str(cost_per_token)) * 1_000_000).normalize()
    # Avoid exponent notation for small numbers, e.g. 2E-2 -> 0.02.
    return format(value, "f")


def model_prices(catalog: dict, previous: dict, overrides: dict) -> dict:
    models: dict = {}
    for key, entry in catalog.items():
        name = key
        for prefix in OWN_API_PREFIXES:
            if key.startswith(prefix):
                name = key.removeprefix(prefix)
                break
        else:
            if not key.startswith(FAMILIES):
                continue
        if "/" in name:
            continue
        if entry.get("mode") not in (None, "chat", "responses"):
            continue
        if entry.get("input_cost_per_token") is None:
            continue
        prices = {
            key: per_million(entry[source])
            for key, source in FIELDS.items()
            if entry.get(source) is not None
        }
        if "input" in prices and "output" in prices:
            models[name] = prices

    # A model the catalog stops listing — usually because it was retired —
    # keeps its last known price, so older sessions in the 30-day history
    # stay priced.
    for name, prices in previous.items():
        models.setdefault(name, prices)

    # Preserve the full reviewed schedule even after the feed adds this model
    # or changes to its standard rate. Historical activity still needs the
    # introductory price, and regenerating must not lose the future cutoff.
    models.update(overrides)
    return dict(sorted(models.items()))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=SOURCE)
    arguments = parser.parse_args()

    # curl rather than urllib: python.org builds ship without CA certificates,
    # and the system curl already trusts the keychain's roots.
    download = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", arguments.source],
        capture_output=True,
        text=True,
        check=True,
    )
    catalog = json.loads(download.stdout)
    scripts = pathlib.Path(__file__).resolve().parent
    destination = scripts.parent / "Shared/Resources/ModelPrices.json"
    previous = json.loads(destination.read_text()).get("models", {}) if destination.exists() else {}
    overrides = json.loads((scripts / "model-price-overrides.json").read_text())
    models = model_prices(catalog, previous, overrides)

    table = {
        "generated": dt.date.today().isoformat(),
        "source": arguments.source,
        "unit": "USD per million tokens",
        "models": models,
    }

    destination.write_text(json.dumps(table, indent=2) + "\n")
    print(f"wrote {len(models)} models to {destination.relative_to(pathlib.Path.cwd())}")


if __name__ == "__main__":
    main()
