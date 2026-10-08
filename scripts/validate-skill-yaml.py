"""Validate skill manifests with PyYAML; no network or model calls."""
import argparse
import re
from pathlib import Path

import yaml


class UniqueLoader(yaml.SafeLoader):
    pass


def mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"Duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, mapping)


def load_mapping(text, label):
    value = yaml.load(text, Loader=UniqueLoader)
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be a YAML mapping")
    return value


def string(value, label, required=True):
    if not isinstance(value, str) or (required and not value.strip()):
        raise ValueError(f"{label} must be a nonempty string")


def validate(root):
    text = (root / "SKILL.md").read_text(encoding="utf-8")
    match = re.match(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|\Z)", text, re.S)
    if not match:
        raise ValueError("SKILL.md needs delimited YAML frontmatter")
    manifest = load_mapping(match[1], "frontmatter")
    for key in ("name", "description"):
        string(manifest.get(key), key)
    name = manifest["name"]
    if name != root.name or len(name) > 64 or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", name):
        raise ValueError("Invalid skill name or directory mismatch")
    if len(manifest["description"]) > 1024:
        raise ValueError("Description exceeds 1024 characters")
    if not text[match.end():].strip():
        raise ValueError("Skill body cannot be empty")
    if "metadata" in manifest:
        if not isinstance(manifest["metadata"], dict) or any(
            not isinstance(k, str) or not isinstance(v, str)
            for k, v in manifest["metadata"].items()
        ):
            raise ValueError("metadata must map strings to strings")
    for key in ("license", "compatibility", "allowed-tools"):
        if key in manifest:
            string(manifest[key], key)
    agent_path = root / "agents" / "openai.yaml"
    if not agent_path.exists():
        return  # Optional for standalone skills.
    agent = load_mapping(agent_path.read_text(encoding="utf-8"), "openai.yaml")
    interface = agent.get("interface")
    if not isinstance(interface, dict):
        raise ValueError("interface must be a mapping")
    for key in ("display_name", "short_description"):
        string(interface.get(key), f"interface.{key}")
    for key in ("default_prompt", "brand_color", "icon_small", "icon_large"):
        if key in interface:
            string(interface[key], f"interface.{key}")
    if "brand_color" in interface and not re.fullmatch(r"#[0-9a-fA-F]{6}", interface["brand_color"]):
        raise ValueError("brand_color must be a six-digit hex color")
    for key in ("icon_small", "icon_large"):
        if key in interface:
            path = interface[key]
            target = (root / path).resolve()
            if not target.is_relative_to(root.resolve()) or not target.is_file():
                raise ValueError(f"{key} must point to a file inside the skill")
    if "policy" in agent:
        policy = agent["policy"]
        if not isinstance(policy, dict) or set(policy) - {"products", "allow_implicit_invocation"}:
            raise ValueError("Invalid policy mapping")
        if "allow_implicit_invocation" in policy and type(policy["allow_implicit_invocation"]) is not bool:
            raise ValueError("allow_implicit_invocation must be boolean")
        if "products" in policy:
            products = policy["products"]
            if not isinstance(products, list) or not products or any(p not in ("CHAT", "CODEX") for p in products):
                raise ValueError("products must contain CHAT and/or CODEX")
    if "dependencies" in agent:
        dependencies = agent["dependencies"]
        if not isinstance(dependencies, dict) or set(dependencies) - {"tools"}:
            raise ValueError("Invalid dependencies mapping")
        tools = dependencies.get("tools", [])
        if not isinstance(tools, list):
            raise ValueError("dependencies.tools must be a list")
        for tool in tools:
            if not isinstance(tool, dict) or tool.get("type") != "mcp":
                raise ValueError("Tool dependencies must be MCP mappings")
            string(tool.get("value"), "tool.value")
            for key in ("description", "transport", "url"):
                if key in tool:
                    string(tool[key], f"tool.{key}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("skill", type=Path)
    args = parser.parse_args()
    try:
        validate(args.skill)
    except (ValueError, OSError, yaml.YAMLError) as error:
        parser.exit(1, f"Skill YAML validation failed: {error}\n")
    print("Skill frontmatter and agent YAML checks passed.")
