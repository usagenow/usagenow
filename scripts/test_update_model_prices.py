"""Offline checks for preserving reviewed price schedules during regeneration."""
import importlib.util
import json
from pathlib import Path
import unittest


SCRIPTS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("model_prices", SCRIPTS / "update-model-prices.py")
PRICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRICES)


class ModelPriceGeneratorTests(unittest.TestCase):
    def setUp(self):
        self.overrides = json.loads((SCRIPTS / "model-price-overrides.json").read_text())

    def test_override_survives_both_missing_and_conflicting_catalog_entries(self):
        for catalog in ({}, {"gemini-4-argon": {"input_cost_per_token": 0.000004, "output_cost_per_token": 0.00002}}):
            with self.subTest(catalog=catalog):
                result = PRICES.model_prices(catalog, {"gemini-4-argon": {"input": "99", "output": "99"}}, self.overrides)
                self.assertEqual(result["gemini-4-argon"], self.overrides["gemini-4-argon"])

    def test_other_models_still_update_and_retired_models_are_preserved(self):
        catalog = {
            "gpt-5-codex": {"input_cost_per_token": 0.00000125, "output_cost_per_token": 0.00001},
            "vertex_ai/gemini-4-argon": {"input_cost_per_token": 99, "output_cost_per_token": 99},
        }
        previous = {"gpt-5-codex": {"input": "9", "output": "9"}, "retired": {"input": "1", "output": "2"}}
        result = PRICES.model_prices(catalog, previous, self.overrides)
        self.assertEqual(result["gpt-5-codex"], {"input": "1.25", "output": "10"})
        self.assertEqual(result["retired"], previous["retired"])
        self.assertNotIn("vertex_ai/gemini-4-argon", result)

    def test_bundled_argon_matches_the_reviewed_schedule(self):
        bundled = json.loads((SCRIPTS.parent / "Shared/Resources/ModelPrices.json").read_text())
        self.assertEqual(bundled["models"]["gemini-4-argon"], self.overrides["gemini-4-argon"])
        argon = self.overrides["gemini-4-argon"]
        self.assertEqual((argon["input"], argon["output"], argon["cacheRead"]), ("2", "10", "0.1"))
        change = argon["changes"][0]
        self.assertEqual(change["effectiveFrom"], "2026-12-01T00:00:00Z")
        self.assertEqual(change["price"], {"input": "4", "output": "20", "cacheRead": "0.2"})


if __name__ == "__main__":
    unittest.main()
