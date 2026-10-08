"""Exercise YAML parsing and invalid field contracts with disposable fixtures."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("validator", Path(__file__).parents[1] / "scripts/validate-skill-yaml.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


class ManifestTests(unittest.TestCase):
    def check(self, header="name: powershell-guardrails\ndescription: Repair commands", body="Instructions", agent=None, valid=False):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "powershell-guardrails"
            (root / "agents").mkdir(parents=True)
            (root / "SKILL.md").write_text(f"---\n{header}\n---\n{body}", encoding="utf-8")
            if agent is not None:
                (root / "agents/openai.yaml").write_text(agent, encoding="utf-8")
            if valid:
                validator.validate(root)
            else:
                with self.assertRaises((ValueError, validator.yaml.YAMLError)):
                    validator.validate(root)

    def test_supported_yaml(self):
        self.check(header="description: >-\n  Repair commands.\n  Skip routine work.\nmetadata:\n  short-description: 'Repair'\nname: powershell-guardrails", valid=True)
        self.check(agent="interface:\n  display_name: Guardrails\n  short_description: Repair commands\npolicy:\n  allow_implicit_invocation: true\n  products: [CODEX]\ndependencies:\n  tools:\n    - type: mcp\n      value: example", valid=True)

    def test_invalid_manifest(self):
        for header in ("name: [broken", "name: powershell-guardrails\ndescription: true", "name: powershell-guardrails\ndescription: A\ndescription: B"):
            with self.subTest(header=header):
                self.check(header=header)
        self.check(body=" ")

    def test_invalid_agent_fields(self):
        interface = "interface:\n  display_name: Guardrails\n  short_description: Repair commands\n"
        for extra in ("policy:\n  allow_implicit_invocation: 'false'", "policy:\n  products: [UNKNOWN]", "dependencies:\n  tools: wrong", "dependencies:\n  tools: [{type: other, value: x}]", "interface: []", "interface:\n  display_name: true\n  short_description: x", "interface:\n  display_name: x\n  short_description: y\n  brand_color: red"):
            with self.subTest(extra=extra):
                self.check(agent=interface + extra if not extra.startswith("interface:") else extra)

    def test_frontmatter_contracts(self):
        for header in (
            "name: another-skill\ndescription: Repair",
            "name: powershell-guardrails\ndescription: Repair\nmetadata: {count: 1}",
            "name: powershell-guardrails\ndescription: Repair\nlicense: false",
            "name: powershell-guardrails\ndescription: " + "x" * 1025,
        ):
            with self.subTest(header=header):
                self.check(header=header)

    def test_icon_containment(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "skill"
            root.mkdir()
            (root / "icon.svg").write_text("<svg/>", encoding="utf-8")
            (base / "outside.svg").write_text("<svg/>", encoding="utf-8")
            interface = {"display_name": "Guardrails", "short_description": "Repair", "icon_small": "icon.svg"}
            validator.validate_interface(interface, root)
            for path in ("../outside.svg", "missing.svg", str(base / "outside.svg")):
                with self.subTest(path=path), self.assertRaises(ValueError):
                    validator.validate_interface({**interface, "icon_small": path}, root)

    def test_optional_sections_and_unknown_fields(self):
        validator.validate_policy({})
        validator.validate_dependencies({})
        for agent in ({"policy": {"unknown": True}}, {"dependencies": {"unknown": []}}):
            with self.subTest(agent=agent), self.assertRaises(ValueError):
                validator.validate_policy(agent)
                validator.validate_dependencies(agent)


if __name__ == "__main__":
    unittest.main()
