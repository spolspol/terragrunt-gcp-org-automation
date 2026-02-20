#!/usr/bin/env python3
"""
Terragrunt Config Renderer — Deep Merge Hierarchy Lookup Tool

Replicates _common/base.hcl's merge logic, rendering the final merged
configuration for any resource path without running Terragrunt.

Usage:
    python3 tg-config-renderer.py [-f {json,yaml,table}] [-k KEY] [--show-sources] [--show-labels] resource_path
    python3 tg-config-renderer.py --full [-f {json,yaml,table}] [-k KEY] [--show-metadata] resource_path

Examples:
    # Hierarchy-only (default)
    python3 scripts/tg-config-renderer.py live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01
    python3 scripts/tg-config-renderer.py -f table --show-sources live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01
    python3 scripts/tg-config-renderer.py --show-labels live/non-production/hub/vpn-gateway/europe-west2/compute/vpn-server
    python3 scripts/tg-config-renderer.py -k project_name -k region live/non-production/development/platform/dp-dev-01/vpc-network

    # Full config render (template + resource deep merge)
    python3 scripts/tg-config-renderer.py --full live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01
    python3 scripts/tg-config-renderer.py --full -f table live/non-production/hub/dns-hub/global/cloud-dns/example-io
    python3 scripts/tg-config-renderer.py --full -k machine_type -k labels live/non-production/development/platform/dp-dev-01/europe-west2/compute/sql-server-01

Requirements:
    pip3 install python-hcl2
    pip3 install pyyaml       # optional, for YAML output
    hcl2json on PATH          # required for --full mode only
"""

import argparse
import io
import json
import os
import re
import shutil
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    import hcl2
except ImportError:
    print("Error: python-hcl2 module not found.")
    print("Install with: pip3 install python-hcl2")
    sys.exit(1)

try:
    import yaml
except ImportError:
    yaml = None


# ─────────────────────────────────────────────────────────────────────────────
# Utility
# ─────────────────────────────────────────────────────────────────────────────

def find_repo_root(start: Path) -> Path:
    """Walk upward from *start* to find the repository root (contains root.hcl)."""
    current = start if start.is_dir() else start.parent
    while True:
        if (current / "root.hcl").is_file():
            return current
        if (current / "_common" / "base.hcl").is_file():
            return current
        parent = current.parent
        if parent == current:
            break
        current = parent
    raise FileNotFoundError(
        f"Could not locate repository root (root.hcl) from {start}"
    )


# ─────────────────────────────────────────────────────────────────────────────
# HclFileLocator
# ─────────────────────────────────────────────────────────────────────────────

class HclFileLocator:
    """Walk upward from a resource path to find each hierarchy file."""

    HIERARCHY_FILES = [
        ("account.hcl", True),
        ("env.hcl", False),
        ("project.hcl", False),
        ("region.hcl", False),
    ]

    def __init__(self, resource_path: Path, repo_root: Path):
        self.resource_path = resource_path.resolve()
        self.repo_root = repo_root.resolve()

    def find_in_parent_folders(self, filename: str) -> Optional[Path]:
        """Mimic Terragrunt's find_in_parent_folders — walk up to repo root."""
        current = self.resource_path
        while current >= self.repo_root:
            candidate = current / filename
            if candidate.is_file():
                return candidate
            if current == self.repo_root:
                break
            current = current.parent
        return None

    def locate_all(self) -> "OrderedDict[str, Optional[Path]]":
        """Return an ordered dict of filename → resolved path (or None)."""
        result: OrderedDict[str, Optional[Path]] = OrderedDict()
        for filename, required in self.HIERARCHY_FILES:
            path = self.find_in_parent_folders(filename)
            if path is None and required:
                raise FileNotFoundError(
                    f"Required hierarchy file '{filename}' not found "
                    f"between {self.resource_path} and {self.repo_root}"
                )
            result[filename] = path

        common_path = self.repo_root / "_common" / "common.hcl"
        if not common_path.is_file():
            raise FileNotFoundError(f"Required file not found: {common_path}")
        result["common.hcl"] = common_path
        return result


# ─────────────────────────────────────────────────────────────────────────────
# HclParser — static HCL file parsing
# ─────────────────────────────────────────────────────────────────────────────

class HclParser:
    """Parse static HCL files using python-hcl2 with a regex fallback."""

    # Keys in common.hcl that contain unresolvable Terragrunt expressions
    _COMMON_SKIP = {"repo_root", "common_root", "templates_root"}

    @staticmethod
    def parse(file_path: str, is_common: bool = False) -> dict:
        try:
            return HclParser._parse_hcl2(file_path, is_common)
        except Exception:
            return HclParser._parse_fallback(file_path, is_common)

    # -- python-hcl2 path -------------------------------------------------------

    @staticmethod
    def _parse_hcl2(file_path: str, is_common: bool) -> dict:
        with open(file_path, "r") as fh:
            parsed = hcl2.load(fh)
        locals_list = parsed.get("locals", [])
        if not locals_list:
            return {}
        result: dict = {}
        for block in locals_list:
            for key, value in block.items():
                if is_common and key in HclParser._COMMON_SKIP:
                    continue
                if HclParser._looks_like_expression(value):
                    continue
                result[key] = value
        return result

    @staticmethod
    def _looks_like_expression(value: Any) -> bool:
        if not isinstance(value, str):
            return False
        if "${" in value:
            return True
        if re.match(r"^[a-z_]+\(", value):
            return True
        return False

    # -- regex fallback ----------------------------------------------------------

    @staticmethod
    def _parse_fallback(file_path: str, is_common: bool) -> dict:
        with open(file_path, "r") as fh:
            content = fh.read()
        block = HclParser._extract_locals(content)
        if block is None:
            return {}
        result = HclParser._parse_block(block)
        if is_common:
            for k in HclParser._COMMON_SKIP:
                result.pop(k, None)
        return result

    @staticmethod
    def _extract_locals(content: str) -> Optional[str]:
        m = re.search(r"locals\s*\{", content)
        if not m:
            return None
        start = m.end()
        depth = 1
        i = start
        while i < len(content) and depth > 0:
            ch = content[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            elif ch == '"':
                i += 1
                while i < len(content) and content[i] != '"':
                    if content[i] == "\\":
                        i += 1
                    i += 1
            elif ch == "#":
                while i < len(content) and content[i] != "\n":
                    i += 1
            i += 1
        return content[start : i - 1]

    @staticmethod
    def _parse_block(content: str) -> dict:
        result: dict = {}
        lines = content.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line or line.startswith("#") or line.startswith("//"):
                i += 1
                continue
            m = re.match(r"(\w+)\s*=\s*(.*)", line)
            if not m:
                i += 1
                continue
            key = m.group(1)
            val = m.group(2).strip()
            # collect multi-line values
            depth = sum(1 for c in val if c in "{[") - sum(1 for c in val if c in "}]")
            while depth > 0 and i + 1 < len(lines):
                i += 1
                val += "\n" + lines[i]
                depth += sum(1 for c in lines[i] if c in "{[")
                depth -= sum(1 for c in lines[i] if c in "}]")
            parsed = HclParser._parse_value(val)
            if parsed is not None:
                result[key] = parsed
            i += 1
        return result

    @staticmethod
    def _parse_value(raw: str) -> Any:
        s = raw.strip()
        if s.startswith('"') and s.endswith('"'):
            inner = s[1:-1]
            if "${" in inner or re.match(r"^[a-z_]+\(", inner):
                return None  # expression
            return inner
        if re.match(r"^-?\d+$", s):
            return int(s)
        if re.match(r"^-?\d+\.\d+$", s):
            return float(s)
        if s == "true":
            return True
        if s == "false":
            return False
        if s == "null":
            return None
        if s.startswith("{"):
            inner = s[1:].rstrip()
            if inner.endswith("}"):
                inner = inner[:-1]
            return HclParser._parse_block(inner)
        if s.startswith("["):
            return HclParser._parse_list(s)
        # function calls / local refs → skip
        if re.match(r"^[a-z_]+\(", s) or s.startswith("local."):
            return None
        return s

    @staticmethod
    def _parse_list(raw: str) -> list:
        inner = raw.strip()
        if inner.startswith("["):
            inner = inner[1:]
        if inner.rstrip().endswith("]"):
            inner = inner.rstrip()[:-1]
        items: list = []
        depth = 0
        current = ""
        in_str = False
        for ch in inner:
            if ch == '"':
                in_str = not in_str
            elif not in_str:
                if ch in "{[":
                    depth += 1
                elif ch in "}]":
                    depth -= 1
                elif ch == "," and depth == 0:
                    items.append(current.strip())
                    current = ""
                    continue
            current += ch
        if current.strip():
            items.append(current.strip())
        result: list = []
        for item in items:
            v = HclParser._parse_value(item)
            if v is not None:
                result.append(v)
        return result


# ─────────────────────────────────────────────────────────────────────────────
# HclExpressionEvaluator — dynamic project.hcl evaluation
# ─────────────────────────────────────────────────────────────────────────────

class HclExpressionEvaluator:
    """Resolve dynamic HCL expressions found in project.hcl files."""

    def __init__(self, project_dir: str, env_locals: dict, account_locals: dict):
        self.project_dir = project_dir
        self.env_locals = env_locals
        self.account_locals = account_locals

    def evaluate(self, file_path: str) -> dict:
        with open(file_path, "r") as fh:
            content = fh.read()
        block = HclParser._extract_locals(content)
        if block is None:
            return {}
        assignments = self._parse_assignments(block)
        # Drop read_terragrunt_config entries (already loaded externally)
        assignments = OrderedDict(
            (k, v) for k, v in assignments.items()
            if "read_terragrunt_config" not in v
        )
        return self._resolve_all(assignments)

    # -- assignment parsing -------------------------------------------------------

    def _parse_assignments(self, content: str) -> OrderedDict:
        result: OrderedDict = OrderedDict()
        lines = content.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line or line.startswith("#") or line.startswith("//"):
                i += 1
                continue
            m = re.match(r"(\w+)\s*=\s*(.*)", line)
            if not m:
                i += 1
                continue
            key = m.group(1)
            val = m.group(2).strip()
            depth = sum(1 for c in val if c in "{[") - sum(1 for c in val if c in "}]")
            while depth > 0 and i + 1 < len(lines):
                i += 1
                val += "\n" + lines[i]
                depth += sum(1 for c in lines[i] if c in "{[")
                depth -= sum(1 for c in lines[i] if c in "}]")
            result[key] = val.strip()
            i += 1
        return result

    # -- multi-pass resolution ----------------------------------------------------

    def _resolve_all(self, assignments: OrderedDict) -> dict:
        resolved: dict = {}
        unresolved = dict(assignments)
        for _ in range(10):
            if not unresolved:
                break
            progress = False
            still: dict = {}
            for name, expr in unresolved.items():
                val = self._resolve_expr(expr, resolved)
                if self._is_unresolved(val):
                    still[name] = expr
                else:
                    resolved[name] = val
                    progress = True
            unresolved = still
            if not progress:
                break
        # final pass for anything remaining
        for name, expr in unresolved.items():
            resolved[name] = self._resolve_expr(expr, resolved)
        # strip any remaining markers
        return {
            k: v for k, v in resolved.items()
            if not (isinstance(v, str) and v.startswith("<unresolved:"))
        }

    @staticmethod
    def _is_unresolved(value: Any) -> bool:
        if isinstance(value, str) and "<unresolved:" in value:
            return True
        if isinstance(value, dict):
            return any(HclExpressionEvaluator._is_unresolved(v) for v in value.values())
        if isinstance(value, list):
            return any(HclExpressionEvaluator._is_unresolved(v) for v in value)
        return False

    # -- expression resolver -------------------------------------------------------

    def _resolve_expr(self, expr: str, resolved: dict) -> Any:
        s = expr.strip()

        # ── static literals ──────────────────────────────────────────────────
        if s.startswith('"') and s.endswith('"'):
            inner = s[1:-1]
            if "${" in inner:
                return self._interpolate(inner, resolved)
            return inner
        if re.match(r"^-?\d+$", s):
            return int(s)
        if re.match(r"^-?\d+\.\d+$", s):
            return float(s)
        if s == "true":
            return True
        if s == "false":
            return False
        if s == "null":
            return None

        # ── basename(get_terragrunt_dir()) ───────────────────────────────────
        if "basename(get_terragrunt_dir())" in s:
            return os.path.basename(self.project_dir)

        # ── try(local.<source>.<key>, "fallback") ────────────────────────────
        m = re.match(r'try\(\s*local\.(\w+)\.(\w+)\s*,\s*"([^"]*)"\s*\)', s)
        if m:
            source, key, fallback = m.group(1), m.group(2), m.group(3)
            if source == "env_vars":
                return self.env_locals.get(key, fallback)
            if source == "account_vars":
                return self.account_locals.get(key, fallback)
            return fallback

        # ── ternary: local.x != "" ? <true> : <false> ───────────────────────
        m = re.match(r'local\.(\w+)\s*!=\s*""\s*\?\s*(.*)\s*:\s*(.+)$', s)
        if m:
            var, t_expr, f_expr = m.group(1), m.group(2).strip(), m.group(3).strip()
            if var not in resolved:
                return f"<unresolved: {s}>"
            return self._resolve_expr(t_expr if resolved[var] else f_expr, resolved)

        # ── local.xxx ────────────────────────────────────────────────────────
        m = re.match(r"local\.(\w+)$", s)
        if m:
            key = m.group(1)
            if key in resolved:
                return resolved[key]
            return f"<unresolved: {s}>"

        # ── map literal ──────────────────────────────────────────────────────
        if s.startswith("{"):
            return self._parse_map(s, resolved)

        # ── list literal ─────────────────────────────────────────────────────
        if s.startswith("["):
            return self._parse_list(s, resolved)

        return s  # pass through unknown

    # -- helpers -------------------------------------------------------------------

    def _interpolate(self, s: str, resolved: dict) -> Any:
        unresolved_flag = [False]

        def _repl(m: re.Match) -> str:
            ref = m.group(1).strip()
            lm = re.match(r"local\.(\w+)", ref)
            if lm:
                key = lm.group(1)
                if key in resolved:
                    return str(resolved[key])
                unresolved_flag[0] = True
                return m.group(0)
            return m.group(0)

        result = re.sub(r"\$\{([^}]+)}", _repl, s)
        if unresolved_flag[0]:
            return f"<unresolved: {result}>"
        return result

    def _parse_map(self, raw: str, resolved: dict) -> dict:
        inner = raw.strip()
        if inner.startswith("{"):
            inner = inner[1:]
        if inner.rstrip().endswith("}"):
            inner = inner.rstrip()[:-1]
        result: dict = {}
        lines = inner.splitlines()
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line or line.startswith("#") or line.startswith("//"):
                i += 1
                continue
            m = re.match(r"(\w+)\s*=\s*(.*)", line)
            if not m:
                i += 1
                continue
            key = m.group(1)
            val = m.group(2).strip()
            depth = sum(1 for c in val if c in "{[") - sum(1 for c in val if c in "}]")
            while depth > 0 and i + 1 < len(lines):
                i += 1
                val += "\n" + lines[i]
                depth += sum(1 for c in lines[i] if c in "{[")
                depth -= sum(1 for c in lines[i] if c in "}]")
            result[key] = self._resolve_expr(val.strip(), resolved)
            i += 1
        return result

    def _parse_list(self, raw: str, resolved: dict) -> list:
        inner = raw.strip()
        if inner.startswith("["):
            inner = inner[1:]
        if inner.rstrip().endswith("]"):
            inner = inner.rstrip()[:-1]
        items: list = []
        depth = 0
        current = ""
        in_str = False
        for ch in inner:
            if ch == '"':
                in_str = not in_str
            elif not in_str:
                if ch in "{[":
                    depth += 1
                elif ch in "}]":
                    depth -= 1
                elif ch == "," and depth == 0:
                    items.append(current.strip())
                    current = ""
                    continue
            current += ch
        if current.strip():
            items.append(current.strip())
        return [self._resolve_expr(it, resolved) for it in items if it]


# ─────────────────────────────────────────────────────────────────────────────
# HierarchyMerger
# ─────────────────────────────────────────────────────────────────────────────

class HierarchyMerger:
    """Flat-merge hierarchy files in base.hcl order and compute derived values."""

    MERGE_ORDER = [
        "account.hcl",
        "env.hcl",
        "project.hcl",
        "region.hcl",
        "common.hcl",
    ]

    def __init__(self, resource_path: Path, repo_root: Path):
        self.resource_path = resource_path.resolve()
        self.repo_root = repo_root.resolve()
        self.sources: dict = {}

    def merge(self) -> Tuple[dict, dict, dict]:
        """Return (merged, derived, standard_labels)."""
        locator = HclFileLocator(self.resource_path, self.repo_root)
        file_paths = locator.locate_all()

        parsed: dict = {}
        for filename in self.MERGE_ORDER:
            path = file_paths.get(filename)
            if path is None:
                parsed[filename] = {}
                continue
            if filename == "project.hcl":
                parsed[filename] = HclExpressionEvaluator(
                    str(path.parent),
                    parsed.get("env.hcl", {}),
                    parsed.get("account.hcl", {}),
                ).evaluate(str(path))
            else:
                is_common = filename == "common.hcl"
                parsed[filename] = HclParser.parse(str(path), is_common=is_common)

        # flat merge — later overrides earlier
        merged: dict = {}
        for filename in self.MERGE_ORDER:
            for key, value in parsed[filename].items():
                merged[key] = value
                self.sources[key] = str(file_paths.get(filename, filename))

        derived = self._derived(merged)
        labels = self._standard_labels(merged, derived)
        return merged, derived, labels

    def get_sources(self) -> dict:
        """Return key → source-file mapping (call after merge)."""
        return dict(self.sources)

    # -- derived values (base.hcl lines 54-60) ------------------------------------

    @staticmethod
    def _derived(merged: dict) -> dict:
        return {
            "name_prefix": merged.get("name_prefix", ""),
            "region": merged.get("region", "europe-west2"),
            "environment": merged.get("environment", ""),
            "environment_type": merged.get("environment_type", ""),
            "project_name": merged.get("project_name", ""),
            "module_versions": merged.get("module_versions", {}),
        }

    # -- standard_labels (base.hcl lines 64-73) -----------------------------------

    @staticmethod
    def _standard_labels(merged: dict, derived: dict) -> dict:
        labels: dict = {
            "environment": derived["environment"],
            "environment_type": derived["environment_type"],
            "managed_by": "terragrunt",
        }
        for label_key in ("org_labels", "env_labels", "project_labels"):
            labels.update(merged.get(label_key, {}))
        return labels


# ─────────────────────────────────────────────────────────────────────────────
# OutputFormatter
# ─────────────────────────────────────────────────────────────────────────────

class OutputFormatter:
    """Render results as JSON, YAML, or table."""

    # ANSI colour codes (used when stdout is a TTY)
    _C_RESET = "\033[0m"
    _C_BOLD = "\033[1m"
    _C_DIM = "\033[2m"
    _C_RED = "\033[31m"
    _C_YELLOW = "\033[33m"
    _C_BLUE = "\033[34m"
    _C_GREEN = "\033[32m"
    _C_CYAN = "\033[36m"

    # Module-level flag: set to True to suppress all colour output.
    _no_colour = False

    # Patterns that indicate an unresolved expression value
    _UNRESOLVED_PAT = re.compile(r"<[^>]+>|templatefile\(")

    @staticmethod
    def _colorize_json(text: str) -> str:
        """Apply jq-style syntax highlighting to JSON text."""
        C = OutputFormatter
        def _repl(m: re.Match) -> str:
            if m.group("key"):
                key_text = m.group("key")
                if key_text == '"unresolved"':
                    return f"{C._C_BOLD}{C._C_RED}{key_text}{C._C_RESET}"
                return f"{C._C_BOLD}{C._C_BLUE}{key_text}{C._C_RESET}"
            if m.group("str"):
                s = m.group("str")
                if C._UNRESOLVED_PAT.search(s):
                    return f"{C._C_RED}{s}{C._C_RESET}"
                return f"{C._C_GREEN}{s}{C._C_RESET}"
            if m.group("null"):
                return f"{C._C_DIM}{m.group('null')}{C._C_RESET}"
            if m.group("bool"):
                return f"{C._C_CYAN}{m.group('bool')}{C._C_RESET}"
            return m.group(0)
        pattern = (
            r'(?P<key>"[^"]*?")\s*(?=:)'
            r'|(?P<str>"[^"]*?")'
            r'|(?P<null>\bnull\b)'
            r'|(?P<bool>\btrue\b|\bfalse\b)'
        )
        return re.sub(pattern, _repl, text)

    @staticmethod
    def _colorize_yaml(text: str) -> str:
        """Apply syntax highlighting to YAML text."""
        C = OutputFormatter
        lines: list = []
        for line in text.split("\n"):
            m = re.match(r"^(\s*)([\w._-]+)(:)(.*)", line)
            if m:
                indent, key, colon, rest = m.groups()
                is_unresolved_key = key == "unresolved"
                key_colour = C._C_RED if is_unresolved_key else C._C_BLUE
                coloured_key = f"{indent}{C._C_BOLD}{key_colour}{key}{C._C_RESET}{colon}"
                rest = rest.strip()
                if not rest or rest == "''":
                    lines.append(f"{coloured_key}")
                elif rest in ("null", "~"):
                    lines.append(f"{coloured_key} {C._C_DIM}{rest}{C._C_RESET}")
                elif rest in ("true", "false"):
                    lines.append(f"{coloured_key} {C._C_CYAN}{rest}{C._C_RESET}")
                elif C._UNRESOLVED_PAT.search(rest):
                    lines.append(f"{coloured_key} {C._C_RED}{rest}{C._C_RESET}")
                elif rest.startswith("'") or rest.startswith('"'):
                    lines.append(f"{coloured_key} {C._C_GREEN}{rest}{C._C_RESET}")
                else:
                    lines.append(f"{coloured_key} {C._C_GREEN}{rest}{C._C_RESET}")
            elif line.strip().startswith("- "):
                m2 = re.match(r"^(\s*- )(.*)", line)
                if m2:
                    val = m2.group(2)
                    val_colour = C._C_RED if C._UNRESOLVED_PAT.search(val) else C._C_GREEN
                    lines.append(f"{m2.group(1)}{val_colour}{val}{C._C_RESET}")
                else:
                    lines.append(line)
            else:
                lines.append(line)
        return "\n".join(lines)

    @staticmethod
    def as_json(data: dict) -> str:
        text = json.dumps(data, indent=2, default=str, ensure_ascii=False)
        if sys.stdout.isatty() and not OutputFormatter._no_colour:
            return OutputFormatter._colorize_json(text)
        return text

    @staticmethod
    def as_yaml(data: dict) -> str:
        if yaml is None:
            print("Error: PyYAML not installed. Use: pip3 install pyyaml", file=sys.stderr)
            sys.exit(1)
        text = yaml.dump(data, default_flow_style=False, sort_keys=False)
        if sys.stdout.isatty() and not OutputFormatter._no_colour:
            return OutputFormatter._colorize_yaml(text)
        return text

    @staticmethod
    def _colorize_table_value(val_str: str) -> str:
        """Apply colour to a table cell value."""
        C = OutputFormatter
        if val_str == '""' or val_str == "[]":
            return f"{C._C_DIM}{val_str}{C._C_RESET}"
        if val_str in ("None", "null"):
            return f"{C._C_DIM}{val_str}{C._C_RESET}"
        if val_str in ("true", "True", "false", "False"):
            return f"{C._C_CYAN}{val_str}{C._C_RESET}"
        return f"{C._C_GREEN}{val_str}{C._C_RESET}"

    @staticmethod
    def as_table(data: dict, sources: Optional[dict] = None) -> str:
        flat = OutputFormatter._flatten(data)
        if not flat:
            return "(empty)"
        colour = sys.stdout.isatty() and not OutputFormatter._no_colour
        C = OutputFormatter

        # Extract metadata keys to show as description above the table
        header_lines: list = []
        meta_keys = ("terraform_source", "unresolved")
        for mk in meta_keys:
            if mk in flat:
                mv = flat.pop(mk)
                if colour:
                    val_colour = C._C_RED if mk == "unresolved" else C._C_GREEN
                    header_lines.append(
                        f"{C._C_DIM}{mk}:{C._C_RESET} {val_colour}{mv}{C._C_RESET}"
                    )
                else:
                    header_lines.append(f"{mk}: {mv}")

        if not flat:
            return "\n".join(header_lines) if header_lines else "(empty)"

        # Strip redundant "inputs." prefix for cleaner table keys
        stripped: OrderedDict = OrderedDict()
        for k, v in flat.items():
            display_key = k[len("inputs."):] if k.startswith("inputs.") else k
            stripped[display_key] = v
        flat = stripped

        max_k = max(len(k) for k in flat)
        # Use first-line width for column sizing (multi-line values don't bloat it)
        def _first_line_len(v: Any) -> int:
            s = str(v)
            nl = s.find("\n")
            return nl if nl >= 0 else len(s)
        max_v = max(_first_line_len(v) for v in flat.values())
        lines: list = []
        if header_lines:
            lines.extend(header_lines)
            lines.append("")
        hdr = f"{'Key':<{max_k}}  {'Value':<{max_v}}"
        if sources:
            hdr += "  Source"
        if colour:
            hdr = f"{C._C_BOLD}{hdr}{C._C_RESET}"
        lines.append(hdr)
        lines.append("-" * (max_k + 2 + max_v + (8 if sources else 0)))
        indent = " " * (max_k + 2)
        for key, val in flat.items():
            val_str = '""' if val == "" else str(val)
            key_display = f"{C._C_BOLD}{C._C_BLUE}{key:<{max_k}}{C._C_RESET}" if colour else f"{key:<{max_k}}"
            # Resolve source for this key
            src = ""
            if sources:
                parts = key.split(".")
                src = sources.get(key, "")
                if not src:
                    src = sources.get(parts[0], "")
                if not src and len(parts) > 1:
                    src = sources.get(parts[1], "")
                if src:
                    src = os.path.basename(src)
            # Format source suffix (padded to align the Source column)
            def _src_suffix(first_line_len: int) -> str:
                if not src:
                    return ""
                pad = max_v - first_line_len
                if pad < 0:
                    pad = 0
                if colour:
                    return f"{' ' * pad}  {C._C_YELLOW}{src}{C._C_RESET}"
                return f"{' ' * pad}  {src}"
            if "\n" in val_str:
                val_lines = val_str.split("\n")
                first = val_lines[0]
                if colour:
                    row = f"{key_display}  {C._colorize_table_value(first)}{_src_suffix(len(first))}"
                    for vl in val_lines[1:]:
                        row += f"\n{indent}{C._colorize_table_value(vl)}"
                else:
                    row = f"{key_display}  {first}{_src_suffix(len(first))}"
                    for vl in val_lines[1:]:
                        row += f"\n{indent}{vl}"
            else:
                if colour:
                    row = f"{key_display}  {C._colorize_table_value(val_str)}{_src_suffix(len(val_str))}"
                else:
                    row = f"{key_display}  {val_str}{_src_suffix(len(val_str))}"
            lines.append(row)
        return "\n".join(lines)

    @staticmethod
    def _format_list(items: list) -> str:
        """Format a list for table display — vertical when more than one item."""
        if not items:
            return "[]"
        if len(items) == 1:
            return json.dumps(items, default=str, ensure_ascii=False)
        lines = ",\n  ".join(json.dumps(item, default=str, ensure_ascii=False) for item in items)
        return f"[\n  {lines},\n]"

    @staticmethod
    def _flatten(data: dict, prefix: str = "") -> "OrderedDict[str, Any]":
        result: OrderedDict = OrderedDict()
        for k, v in data.items():
            full_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict) and v:
                result.update(OutputFormatter._flatten(v, full_key))
            elif isinstance(v, list):
                result[full_key] = OutputFormatter._format_list(v)
            else:
                result[full_key] = v
        return result


# ─────────────────────────────────────────────────────────────────────────────
# Hcl2JsonParser — parse HCL via external hcl2json binary
# ─────────────────────────────────────────────────────────────────────────────

class Hcl2JsonParser:
    """Wraps the hcl2json Go binary for full HCL2 grammar support."""

    @staticmethod
    def is_available() -> bool:
        return shutil.which("hcl2json") is not None

    @staticmethod
    def parse(file_path: str) -> dict:
        """Run ``hcl2json -simplify`` on *file_path* and return parsed JSON."""
        try:
            result = subprocess.run(
                ["hcl2json", "-simplify", file_path],
                capture_output=True, text=True, timeout=30,
            )
        except FileNotFoundError:
            raise RuntimeError(
                "hcl2json not found on PATH.\n"
                "Install: go install github.com/tmccombs/hcl2json@latest\n"
                "     or: download from https://github.com/tmccombs/hcl2json/releases"
            )
        if result.returncode != 0:
            raise RuntimeError(f"hcl2json failed on {file_path}: {result.stderr.strip()}")
        return json.loads(result.stdout)

    @staticmethod
    def extract_blocks(parsed: dict) -> dict:
        """Extract key block types from hcl2json output.

        Returns dict with keys: terraform, locals, inputs, include, dependency.
        hcl2json returns ``inputs`` as a dict and ``locals``/``terraform``
        as lists.  Normalise ``inputs`` into a list for uniform handling.
        """
        raw_inputs = parsed.get("inputs", {})
        if isinstance(raw_inputs, (dict, str)):
            inputs_list = [raw_inputs]
        else:
            inputs_list = raw_inputs
        raw_locals = parsed.get("locals", [{}])
        locals_list = [raw_locals] if isinstance(raw_locals, dict) else raw_locals
        return {
            "terraform": parsed.get("terraform", [{}]),
            "locals": locals_list,
            "inputs": inputs_list,
            "include": parsed.get("include", {}),
            "dependency": parsed.get("dependency", {}),
        }


# ─────────────────────────────────────────────────────────────────────────────
# IncludeResolver — identify template and base includes
# ─────────────────────────────────────────────────────────────────────────────

class IncludeResolver:
    """Parse include blocks from hcl2json output to find template and base paths."""

    def __init__(self, include_blocks: dict, resource_path: Path, repo_root: Path):
        self.include_blocks = include_blocks
        self.resource_path = resource_path
        self.repo_root = repo_root

    def find_template(self) -> Optional[Path]:
        """Return the resolved path for the include with merge_strategy = 'deep'."""
        for name, block_list in self.include_blocks.items():
            blocks = block_list if isinstance(block_list, list) else [block_list]
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("merge_strategy") == "deep":
                    raw_path = block.get("path", "")
                    return self._resolve_path(raw_path)
        return None

    def find_exposed_includes(self) -> Dict[str, Path]:
        """Return ``{name: resolved_path}`` for includes with ``expose = true``.

        Excludes ``root`` and ``base`` (handled separately) and the template
        (has ``merge_strategy = "deep"``).
        """
        result: Dict[str, Path] = {}
        skip = {"root", "base"}
        for name, block_list in self.include_blocks.items():
            if name in skip:
                continue
            blocks = block_list if isinstance(block_list, list) else [block_list]
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                if block.get("merge_strategy") == "deep":
                    continue  # already handled as template
                if block.get("expose") is True:
                    raw_path = block.get("path", "")
                    resolved = self._resolve_path(raw_path)
                    if resolved:
                        result[name] = resolved
        return result

    def _resolve_path(self, raw: str) -> Optional[Path]:
        """Resolve a path expression like ``${get_repo_root()}/_common/templates/x.hcl``."""
        resolved = raw
        # Strip outer ${...} wrapper added by hcl2json
        m = re.match(r"^\$\{(.+)\}$", resolved, re.DOTALL)
        if m:
            resolved = m.group(1)
        resolved = re.sub(r"\$\{get_repo_root\(\)\}", str(self.repo_root), resolved)
        resolved = re.sub(r"get_repo_root\(\)", str(self.repo_root), resolved)
        resolved = re.sub(
            r'find_in_parent_folders\("([^"]+)"\)',
            lambda m: self._find_in_parents(m.group(1)),
            resolved,
        )
        p = Path(resolved)
        if not p.is_absolute():
            p = self.resource_path / p
        p = p.resolve()
        return p if p.is_file() else None

    def _find_in_parents(self, filename: str) -> str:
        current = self.resource_path
        while current >= self.repo_root:
            candidate = current / filename
            if candidate.is_file():
                return str(candidate)
            if current == self.repo_root:
                break
            current = current.parent
        return filename


# ─────────────────────────────────────────────────────────────────────────────
# DependencyResolver — extract mock_outputs from dependency blocks
# ─────────────────────────────────────────────────────────────────────────────

class DependencyResolver:
    """Extract mock_outputs and config_path from dependency blocks."""

    def __init__(self, dep_blocks: dict):
        self.mocks: Dict[str, dict] = {}
        self.paths: Dict[str, str] = {}
        self._parse(dep_blocks)

    def _parse(self, dep_blocks: dict) -> None:
        for name, block_list in dep_blocks.items():
            blocks = block_list if isinstance(block_list, list) else [block_list]
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                # Store config_path
                cp = block.get("config_path", "")
                if isinstance(cp, str) and cp:
                    self.paths[name] = cp
                # Store mock_outputs (kept for internal use by complex expressions)
                mock = block.get("mock_outputs")
                if isinstance(mock, dict):
                    self.mocks[name] = mock
                elif isinstance(mock, list) and mock:
                    self.mocks[name] = mock[0] if isinstance(mock[0], dict) else {}

    def resolve_ref(self, dep_name: str, output_key: str) -> str:
        """Resolve ``dependency.<dep_name>.outputs.<output_key>``.

        Returns a ``#dependency`` token showing the config path and output key.
        """
        path = self.paths.get(dep_name, dep_name)
        return f"#dependency|{path}, {output_key}|"

    def get_all_mocks(self) -> Dict[str, dict]:
        return dict(self.mocks)


# ─────────────────────────────────────────────────────────────────────────────
# ExpressionResolver — resolve HCL expressions against context
# ─────────────────────────────────────────────────────────────────────────────

class ExpressionResolver:
    """Best-effort resolver for HCL expressions in inputs/locals."""

    def __init__(
        self,
        hierarchy: dict,
        derived: dict,
        labels: dict,
        dep_resolver: DependencyResolver,
        resource_path: Path,
        repo_root: Optional[Path] = None,
    ):
        # Build the context that ``include.base.locals.*`` would expose
        self.base_locals: dict = {
            "merged": hierarchy,
            "region": derived.get("region", "europe-west2"),
            "environment": derived.get("environment", ""),
            "environment_type": derived.get("environment_type", ""),
            "name_prefix": derived.get("name_prefix", ""),
            "project_name": derived.get("project_name", ""),
            "module_versions": derived.get("module_versions", {}),
            "resource_name": resource_path.name,
            "standard_labels": labels,
        }
        self.dep_resolver = dep_resolver
        self.resource_path = resource_path
        self.repo_root = repo_root or resource_path
        self.locals_ctx: dict = {}
        self.unresolved: List[str] = []
        self._rtc_cache: Dict[str, Any] = {}  # cache for read_terragrunt_config
        # Extra exposed includes: {include_name: {locals dict}}
        self.extra_includes: Dict[str, dict] = {}

    def set_locals_context(self, ctx: dict) -> None:
        self.locals_ctx = ctx

    def resolve_value(self, value: Any) -> Any:
        """Recursively resolve a value from hcl2json parsed output."""
        if isinstance(value, str):
            return self._resolve_string(value)
        if isinstance(value, dict):
            return {k: self.resolve_value(v) for k, v in value.items()}
        if isinstance(value, list):
            return [self.resolve_value(v) for v in value]
        return value

    def resolve_locals(self, locals_blocks: list, seed: Optional[dict] = None) -> dict:
        """Resolve locals blocks (list of dicts from hcl2json) into a flat dict.

        *seed* provides pre-resolved values (e.g. hierarchy data that templates
        normally obtain via ``read_terragrunt_config``).
        """
        raw: dict = {}
        for block in locals_blocks:
            if isinstance(block, dict):
                raw.update(block)

        resolved: dict = dict(seed) if seed else {}
        # Remove from raw anything already seeded (don't re-resolve)
        remaining = {k: v for k, v in raw.items() if k not in resolved}
        for _ in range(10):
            if not remaining:
                break
            progress = False
            still: dict = {}
            for k, v in remaining.items():
                # Defer if the raw expression references another unresolved local.
                # This prevents try(local.X, null) from resolving to null before
                # local.X has been resolved in a later pass.
                raw_str = str(v)
                refs_pending = any(
                    f"local.{other}" in raw_str
                    for other in remaining if other != k
                )
                if refs_pending:
                    still[k] = v
                    continue
                self.locals_ctx = resolved
                saved_unresolved = list(self.unresolved)
                result = self.resolve_value(v)
                if self._has_placeholder(result):
                    still[k] = v
                    self.unresolved = saved_unresolved  # revert — will retry
                else:
                    resolved[k] = result
                    progress = True
            remaining = still
            if not progress:
                break
        # Final pass for anything left
        for k, v in remaining.items():
            self.locals_ctx = resolved
            resolved[k] = self.resolve_value(v)
        self.locals_ctx = resolved
        return resolved

    def resolve_inputs(self, inputs_blocks: list) -> dict:
        """Resolve inputs blocks (list of dicts from hcl2json) into a flat dict.

        Handles both dict-style inputs and expression-style
        (e.g. ``merge(local.x, {...})``).
        """
        raw: dict = {}
        for block in inputs_blocks:
            if isinstance(block, dict):
                raw.update(block)
            elif isinstance(block, str):
                # inputs = merge(...) or inputs = local.x — resolve as expression
                resolved = self.resolve_value(block)
                if isinstance(resolved, dict):
                    raw.update(resolved)
        return {k: self.resolve_value(v) for k, v in raw.items()}

    # -- internal ---------------------------------------------------------------

    def _resolve_string(self, s: str) -> Any:
        # Pure interpolation: "${expr}" — depth-aware check for single outer block
        if s.startswith("${") and s.endswith("}"):
            # Walk from position 2 tracking depth to find matching closing }
            depth = 1
            in_str = False
            i = 2
            while i < len(s):
                ch = s[i]
                if ch == '\\' and in_str:
                    i += 2  # skip escaped char
                    continue
                if ch == '"':
                    in_str = not in_str
                elif not in_str:
                    if ch == '{':
                        depth += 1
                    elif ch == '}':
                        depth -= 1
                        if depth == 0:
                            # Closing brace at end of string → pure interpolation
                            if i == len(s) - 1:
                                return self._resolve_expr(s[2:-1].strip())
                            break  # closing brace before end → mixed
                i += 1

        # Mixed interpolation: "prefix-${expr}-suffix" or multiple blocks
        if "${" in s:
            def _repl(match: re.Match) -> str:
                val = self._resolve_expr(match.group(1).strip())
                return str(val) if not isinstance(val, str) or not val.startswith("<") else match.group(0)
            result = re.sub(r"\$\{([^}]+)}", _repl, s)
            if "${" in result:
                self._track_unresolved(result)
            return result

        return s

    def _resolve_expr(self, expr: str) -> Any:
        """Resolve a single HCL expression."""
        e = expr.strip()

        # ── Literals ─────────────────────────────────────────────────────────
        if e == "{}":
            return {}
        if e == "[]":
            return []
        if e == "true":
            return True
        if e == "false":
            return False
        if e == "null":
            return None
        if re.match(r"^-?\d+$", e):
            return int(e)
        if re.match(r"^-?\d+\.\d+$", e):
            return float(e)
        if e.startswith('"') and e.endswith('"'):
            inner = e[1:-1]
            if "${" not in inner:
                return inner
            # Quoted string with interpolation — resolve inner ${...}
            return self._resolve_string(inner)

        # ── Compound literals (must come before substring-match patterns) ────
        # HCL map literal: { key = "value", ... }
        if e.startswith("{") and e.endswith("}"):
            inner = e[1:-1].strip()
            if re.match(r"\s*for\s+", inner):
                result = self._resolve_for_expr(inner, is_map=True)
                if result is not None:
                    return result
                self._track_unresolved("<for-expression>")
                return "<for-expression>"
            return self._parse_hcl_map(inner)

        # HCL list literal: [expr, ...]
        if e.startswith("[") and e.endswith("]"):
            inner = e[1:-1].strip()
            if not inner:
                return []
            if re.match(r"\s*for\s+", inner):
                result = self._resolve_for_expr(inner, is_map=False)
                if result is not None:
                    return result
                self._track_unresolved("<for-expression>")
                return "<for-expression>"
            parts = self._split_top_level(inner)
            return [self._resolve_expr(p.strip()) for p in parts]

        # ── Simple references (anchored to full expression) ──────────────────
        # include.<name>.locals.X.Y... (with optional [index] suffix)
        m = re.match(r"^include\.(\w+)\.locals\.([\w.]+)(.*)$", e)
        if m:
            inc_name, dotted, suffix = m.group(1), m.group(2), m.group(3).strip()
            # Pick the right context dict
            if inc_name == "base":
                ctx = self.base_locals
            else:
                ctx = self.extra_includes.get(inc_name)
            if ctx is not None:
                if not suffix or suffix.startswith("["):
                    val = self._dot_lookup(ctx, dotted)
                    if suffix:
                        idx_m = re.match(r"^\[(.+?)\](.*)", suffix)
                        if idx_m and isinstance(val, (list, dict)):
                            idx_expr = idx_m.group(1).strip()
                            idx_val = self._resolve_expr(idx_expr)
                            if isinstance(idx_val, int) and isinstance(val, list):
                                if 0 <= idx_val < len(val):
                                    return val[idx_val]
                            elif isinstance(idx_val, str) and isinstance(val, dict):
                                if idx_val in val:
                                    return val[idx_val]
                    return val
                # suffix contains operators (==, !=, ?) — fall through to
                # comparison/ternary handlers below

        # dependency.X.outputs.Y (with optional [index] or .subkey)
        m = re.match(r"^dependency\.([\w-]+)\.outputs\.(\w+)(.*)$", e)
        if m:
            dep_name, output_key, suffix = m.group(1), m.group(2), m.group(3).strip()
            if suffix:
                # Resolve local.X references in the suffix for a clearer token
                resolved_suffix = re.sub(
                    r'local\.\w+',
                    lambda ms: str(self._resolve_expr(ms.group(0))),
                    suffix,
                )
                path = self.dep_resolver.paths.get(dep_name, dep_name)
                return f"#dependency|{path}, {output_key}{resolved_suffix}|"
            return self.dep_resolver.resolve_ref(dep_name, output_key)

        # local.X.Y... (with optional [index] suffix)
        m = re.match(r"^local\.([\w.]+)(.*)$", e)
        if m:
            suffix = m.group(2).strip()
            if not suffix or suffix.startswith("["):
                val = self._dot_lookup(self.locals_ctx, m.group(1))
                if suffix:
                    idx_m = re.match(r"^\[(.+?)\](.*)", suffix)
                    if idx_m and isinstance(val, (list, dict)):
                        idx_expr = idx_m.group(1).strip()
                        idx_val = self._resolve_expr(idx_expr)
                        if isinstance(idx_val, int) and isinstance(val, list):
                            if 0 <= idx_val < len(val):
                                return val[idx_val]
                        elif isinstance(idx_val, str) and isinstance(val, dict):
                            if idx_val in val:
                                return val[idx_val]
                return val

        # basename(get_terragrunt_dir())
        if e == "basename(get_terragrunt_dir())":
            return self.resource_path.name

        # dirname / basename(dirname(...)) chains on get_terragrunt_dir()
        m_dir = re.match(r"^((?:basename|dirname)\()+get_terragrunt_dir\(\)((?:\))+)$", e)
        if m_dir:
            path = self.resource_path
            # Strip outer function calls and apply from inside out
            funcs: list = re.findall(r"(basename|dirname)\(", e)
            for fn in reversed(funcs):
                if fn == "dirname":
                    path = path.parent
                elif fn == "basename":
                    path = Path(path.name)
            return str(path)

        # get_terragrunt_dir()
        if e == "get_terragrunt_dir()":
            return str(self.resource_path)

        # get_env(name, default) — resolve to default value (offline, no env access)
        m = re.match(r'get_env\((.+)\)$', e, re.DOTALL)
        if m:
            parts = self._split_top_level(m.group(1).strip())
            if len(parts) >= 2:
                return self._resolve_expr(parts[1].strip())
            return ""

        # ── Function calls ───────────────────────────────────────────────────
        # try(expr, fallback)
        m = re.match(r"try\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_try(m.group(1).strip())

        # merge(a, b, ...)
        m = re.match(r"merge\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_merge(m.group(1).strip())

        # format(fmt, arg1, arg2, ...) — Terraform sprintf
        m = re.match(r"format\((.+)\)$", e, re.DOTALL)
        if m:
            parts = self._split_top_level(m.group(1).strip())
            if parts:
                fmt_val = self._resolve_expr(parts[0].strip())
                if isinstance(fmt_val, str):
                    args = [self._resolve_expr(p.strip()) for p in parts[1:]]
                    try:
                        return fmt_val % tuple(args)
                    except (TypeError, ValueError):
                        pass

        # lookup(map, key, default)
        m = re.match(r"lookup\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_lookup(m.group(1).strip())

        # replace(str, old, new)
        m = re.match(r"replace\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_replace(m.group(1).strip())

        # trimsuffix(str, suffix)
        m = re.match(r"trimsuffix\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_trimsuffix(m.group(1).strip())

        # concat(list1, list2, ...)
        m = re.match(r"concat\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_concat(m.group(1).strip())

        # distinct(list)
        m = re.match(r"distinct\((.+)\)$", e, re.DOTALL)
        if m:
            val = self._resolve_expr(m.group(1).strip())
            if isinstance(val, list):
                seen: list = []
                for item in val:
                    if item not in seen:
                        seen.append(item)
                return seen
            return val

        # flatten(list)
        m = re.match(r"flatten\((.+)\)$", e, re.DOTALL)
        if m:
            val = self._resolve_expr(m.group(1).strip())
            if isinstance(val, list):
                flat: list = []
                for item in val:
                    if isinstance(item, list):
                        flat.extend(item)
                    else:
                        flat.append(item)
                return flat
            return val

        # keys(map)
        m = re.match(r"keys\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_keys(m.group(1).strip())

        # values(map)
        m = re.match(r"values\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_values(m.group(1).strip())

        # sort(list)
        m = re.match(r"sort\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_sort(m.group(1).strip())

        # contains(list, value)
        m = re.match(r"contains\((.+)\)$", e, re.DOTALL)
        if m:
            return self._resolve_contains(m.group(1).strip())

        # index(list, value)
        m = re.match(r"index\((.+)\)$", e, re.DOTALL)
        if m:
            parts = self._split_top_level(m.group(1).strip())
            if len(parts) == 2:
                collection = self._resolve_expr(parts[0].strip())
                value = self._resolve_expr(parts[1].strip())
                if isinstance(collection, list):
                    try:
                        return collection.index(value)
                    except ValueError:
                        pass
            return f"<index(...)>"

        # tostring(expr)
        m = re.match(r"tostring\((.+)\)$", e, re.DOTALL)
        if m:
            val = self._resolve_expr(m.group(1).strip())
            return str(val)

        # startswith(string, prefix) / endswith(string, suffix)
        m = re.match(r"(startswith|endswith)\((.+)\)$", e, re.DOTALL)
        if m:
            fn = m.group(1)
            parts = self._split_top_level(m.group(2).strip())
            if len(parts) == 2:
                s = self._resolve_expr(parts[0].strip())
                affix = self._resolve_expr(parts[1].strip())
                if isinstance(s, str) and isinstance(affix, str):
                    return s.startswith(affix) if fn == "startswith" else s.endswith(affix)

        # lower(str) / upper(str) / title(str)
        m = re.match(r"(lower|upper|title)\((.+)\)$", e, re.DOTALL)
        if m:
            fn, arg = m.group(1), self._resolve_expr(m.group(2).strip())
            if isinstance(arg, str) and not arg.startswith("<"):
                if fn == "lower":
                    return arg.lower()
                elif fn == "upper":
                    return arg.upper()
                elif fn == "title":
                    return arg.title()
            return f"<{fn}({arg})>"

        # split(separator, string)
        m = re.match(r"split\((.+)\)$", e, re.DOTALL)
        if m:
            parts = self._split_top_level(m.group(1).strip())
            if len(parts) == 2:
                sep = self._resolve_expr(parts[0].strip())
                val = self._resolve_expr(parts[1].strip())
                if isinstance(sep, str) and isinstance(val, str) and not val.startswith("<"):
                    return val.split(sep)
            return f"<split(...)>"

        # substr(string, offset, length)
        m = re.match(r"substr\((.+)\)$", e, re.DOTALL)
        if m:
            parts = self._split_top_level(m.group(1).strip())
            if len(parts) == 3:
                val = self._resolve_expr(parts[0].strip())
                offset = self._resolve_expr(parts[1].strip())
                length = self._resolve_expr(parts[2].strip())
                if isinstance(val, str) and not val.startswith("<"):
                    try:
                        offset = int(offset)
                        length = int(length)
                        # HCL substr: negative offset counts from end
                        if offset < 0:
                            offset = max(0, len(val) + offset)
                        return val[offset:offset + length]
                    except (ValueError, TypeError):
                        pass
            return f"<substr(...)>"

        # templatefile(...)
        if e.startswith("templatefile("):
            self._track_unresolved("<templatefile(...)>")
            return "<templatefile(...)>"

        # read_terragrunt_config(path)
        if e.startswith("read_terragrunt_config("):
            return self._resolve_read_terragrunt_config(e)

        # for expressions (standalone, not inside brackets)
        if re.match(r"for\s+", e):
            self._track_unresolved("<for-expression>")
            return "<for-expression>"

        # ternary: condition ? true : false (depth-aware, lowest precedence)
        q_idx = self._find_depth0_token(e, " ? ")
        if q_idx >= 0:
            cond_str = e[:q_idx].strip()
            rest = e[q_idx + 3:]
            c_idx = self._find_depth0_token(rest, " : ")
            if c_idx >= 0:
                t_str = rest[:c_idx].strip()
                f_str = rest[c_idx + 3:].strip()
                return self._resolve_ternary(cond_str, t_str, f_str)

        # comparison operators: expr != expr, expr == expr (depth-aware)
        for op in (" != ", " == "):
            op_idx = self._find_depth0_token(e, op)
            if op_idx >= 0:
                lhs = self._resolve_expr(e[:op_idx].strip())
                rhs = self._resolve_expr(e[op_idx + len(op):].strip())
                if not (isinstance(lhs, str) and lhs.startswith("<")) and \
                   not (isinstance(rhs, str) and rhs.startswith("<")):
                    if op == " != ":
                        return lhs != rhs
                    else:
                        return lhs == rhs
                break  # found operator but couldn't resolve — fall through

        # complex function calls we can't resolve
        if re.match(r"^\w+\(", e):
            short = re.sub(r"\s+", " ", e)[:80]
            self._track_unresolved(f"<{short}>")
            return f"<{short}>"

        # inputs.X — Terragrunt self-reference (unresolvable statically)
        if re.match(r"^inputs\.\w+", e):
            self._track_unresolved(f"<{e}>")
            return f"<{e}>"

        # bare identifier — resolve from locals (handles for-loop variables)
        if re.match(r"^\w+$", e) and e in self.locals_ctx:
            return self.locals_ctx[e]

        # fallback: return as-is
        return e

    def _resolve_try(self, args_str: str) -> Any:
        """Resolve try(expr1, expr2, ...) — try each arg in order, return first success.

        Suppresses unresolved tracking for args that fail when a later arg succeeds.
        """
        parts = self._split_top_level(args_str)
        if not parts:
            return f"<try({args_str})>"
        for part in parts:
            saved_unresolved = list(self.unresolved)
            val = self._resolve_expr(part.strip())
            if not (isinstance(val, str) and (val.startswith("<") or "${" in val)):
                return val
            # This arg failed — revert any unresolved entries it added
            self.unresolved = saved_unresolved
        # All failed — resolve last arg and keep its unresolved entries
        return self._resolve_expr(parts[-1].strip())

    def _resolve_merge(self, args_str: str) -> Any:
        """Resolve merge(map1, map2, ...) — merge dicts left to right."""
        parts = self._split_top_level(args_str)
        result: dict = {}
        for part in parts:
            val = self._resolve_expr(part.strip())
            if isinstance(val, dict):
                result.update(val)
            elif isinstance(val, str) and val.startswith("<"):
                continue  # skip unresolvable
        return result if result else f"<merge({args_str[:40]})>"

    def _resolve_concat(self, args_str: str) -> Any:
        """Resolve concat(list1, list2, ...) — concatenate lists."""
        parts = self._split_top_level(args_str)
        result: list = []
        all_resolved = True
        for part in parts:
            val = self._resolve_expr(part.strip())
            if isinstance(val, list):
                result.extend(val)
            elif isinstance(val, str) and val.startswith("<"):
                all_resolved = False
            else:
                result.append(val)
        if not all_resolved:
            short = re.sub(r"\s+", " ", args_str)[:80]
            self._track_unresolved(f"<concat({short})>")
            return f"<concat({short})>"
        return result

    def _resolve_lookup(self, args_str: str) -> Any:
        """Resolve lookup(map, key, default)."""
        parts = self._split_top_level(args_str)
        if len(parts) < 2:
            return f"<lookup({args_str})>"
        map_val = self._resolve_expr(parts[0].strip())
        key_val = self._resolve_expr(parts[1].strip())
        default_val = self._resolve_expr(parts[2].strip()) if len(parts) > 2 else None
        if isinstance(key_val, str):
            key_val = key_val.strip('"')
        if isinstance(map_val, dict):
            return map_val.get(key_val, default_val)
        return default_val if default_val is not None else f"<lookup(...)>"

    def _resolve_replace(self, args_str: str) -> Any:
        """Resolve replace(string, old, new)."""
        parts = self._split_top_level(args_str)
        if len(parts) != 3:
            return f"<replace({args_str})>"
        s = self._resolve_expr(parts[0].strip())
        old = self._resolve_expr(parts[1].strip())
        new = self._resolve_expr(parts[2].strip())
        if isinstance(s, str) and isinstance(old, str) and isinstance(new, str):
            return s.replace(old.strip('"'), new.strip('"'))
        return f"<replace(...)>"

    def _resolve_trimsuffix(self, args_str: str) -> Any:
        """Resolve trimsuffix(string, suffix)."""
        parts = self._split_top_level(args_str)
        if len(parts) != 2:
            return f"<trimsuffix({args_str})>"
        s = self._resolve_expr(parts[0].strip())
        suffix = self._resolve_expr(parts[1].strip())
        if isinstance(s, str) and isinstance(suffix, str):
            suffix = suffix.strip('"')
            return s.removesuffix(suffix)
        return f"<trimsuffix(...)>"

    def _resolve_ternary(self, cond: str, t_expr: str, f_expr: str) -> Any:
        """Resolve condition ? true_val : false_val."""
        cond_val = self._resolve_expr(cond)
        if isinstance(cond_val, bool):
            return self._resolve_expr(t_expr if cond_val else f_expr)
        if isinstance(cond_val, str) and not cond_val.startswith("<"):
            # simple truthy check
            return self._resolve_expr(t_expr if cond_val else f_expr)
        return self._resolve_expr(t_expr)  # best-effort: assume true

    def _resolve_for_expr(self, inner: str, is_map: bool) -> Any:
        """Best-effort resolve for-expressions.

        Handles common patterns found in this repo:
        - Map pivot: ``for role in distinct(flatten(values(local.X))) : role => sort(...)``
        - List filter: ``for k, v in map : k if contains(v, item)``

        Returns None if the expression can't be resolved.
        """
        try:
            # Parse: for VAR[, VAR2] in ITERABLE : BODY
            # Split at depth-0 ' in ' and ' : ' tokens
            m_vars = re.match(r"for\s+([\w,\s]+)\s+in\s+", inner)
            if not m_vars:
                return None
            var_str = m_vars.group(1).strip()
            vars_list = [v.strip() for v in var_str.split(",")]
            rest = inner[m_vars.end():]

            # Find the for-expression ` :` separator at bracket depth 0.
            # Must match ` :` followed by whitespace (space, newline, tab) to
            # avoid matching a ternary ` : ` later in the expression.
            colon_idx = self._find_depth0_for_colon(rest)
            if colon_idx < 0:
                return None
            iterable_expr = rest[:colon_idx].strip()
            # Skip ` :` plus the whitespace char
            body = rest[colon_idx + 2:].strip()

            # Resolve the iterable
            iterable = self._resolve_expr(iterable_expr)
            if not isinstance(iterable, (list, dict)):
                return None

            if is_map:
                # Find ` => ` in body at depth 0
                arrow_idx = self._find_depth0_token(body, " => ")
                if arrow_idx < 0:
                    arrow_idx = self._find_depth0_token(body, "=>")
                if arrow_idx < 0:
                    return None
                sep_len = 4 if body[arrow_idx:arrow_idx+4] == " => " else 2
                key_expr = body[:arrow_idx].strip()
                val_expr = body[arrow_idx + sep_len:].strip()

                items = list(iterable) if isinstance(iterable, list) else list(iterable.keys())
                result: dict = {}
                saved_locals = dict(self.locals_ctx)
                for item in items:
                    self.locals_ctx[vars_list[0]] = item
                    if len(vars_list) > 1 and isinstance(iterable, dict):
                        self.locals_ctx[vars_list[1]] = iterable[item]
                    key = self._resolve_expr(key_expr)
                    val = self._resolve_expr(val_expr)
                    if isinstance(key, str):
                        result[key] = val
                self.locals_ctx = saved_locals
                return result

            else:
                # List for: check for ` if ` condition at depth 0
                if_idx = self._find_depth0_token(body, " if ")
                if if_idx >= 0:
                    body_expr = body[:if_idx].strip()
                    cond_expr = body[if_idx + 4:].strip()
                else:
                    body_expr = body
                    cond_expr = None

                result_list: list = []
                saved_locals = dict(self.locals_ctx)
                if isinstance(iterable, dict):
                    for k, v in iterable.items():
                        self.locals_ctx[vars_list[0]] = k
                        if len(vars_list) > 1:
                            self.locals_ctx[vars_list[1]] = v
                        if cond_expr:
                            cond_val = self._resolve_expr(cond_expr)
                            if cond_val is False:
                                continue
                        result_list.append(self._resolve_expr(body_expr))
                else:
                    for item in iterable:
                        self.locals_ctx[vars_list[0]] = item
                        if cond_expr:
                            cond_val = self._resolve_expr(cond_expr)
                            if cond_val is False:
                                continue
                        result_list.append(self._resolve_expr(body_expr))
                self.locals_ctx = saved_locals
                return result_list

        except Exception:
            pass
        return None

    def _find_depth0_token(self, s: str, token: str) -> int:
        """Find the position of *token* in *s* that occurs at bracket depth 0."""
        depth = 0
        in_str = False
        tlen = len(token)
        for i, ch in enumerate(s):
            if ch == '"' and (i == 0 or s[i - 1] != '\\'):
                in_str = not in_str
            elif not in_str:
                if ch in "({[":
                    depth += 1
                elif ch in ")}]":
                    depth -= 1
                elif depth == 0 and s[i:i + tlen] == token:
                    return i
        return -1

    def _find_depth0_for_colon(self, s: str) -> int:
        """Find the for-expression ` :` separator at bracket depth 0.

        Matches ` :` (space-colon) followed by any whitespace character
        (space, newline, tab). This avoids matching a ternary ` : ` that
        may appear later in the body.
        """
        depth = 0
        in_str = False
        for i, ch in enumerate(s):
            if ch == '"' and (i == 0 or s[i - 1] != '\\'):
                in_str = not in_str
            elif not in_str:
                if ch in "({[":
                    depth += 1
                elif ch in ")}]":
                    depth -= 1
                elif depth == 0 and ch == ':' and i > 0 and s[i - 1] == ' ':
                    # Check next char is whitespace (or end of string)
                    if i + 1 >= len(s) or s[i + 1] in ' \t\n\r':
                        return i - 1  # return position of the space before `:`
        return -1

    def _resolve_contains(self, args_str: str) -> Any:
        """Resolve contains(list, value)."""
        parts = self._split_top_level(args_str)
        if len(parts) != 2:
            return f"<contains(...)>"
        collection = self._resolve_expr(parts[0].strip())
        value = self._resolve_expr(parts[1].strip())
        if isinstance(collection, list):
            return value in collection
        if isinstance(collection, dict):
            return value in collection
        return f"<contains(...)>"

    def _resolve_keys(self, args_str: str) -> Any:
        """Resolve keys(map)."""
        val = self._resolve_expr(args_str.strip())
        if isinstance(val, dict):
            return list(val.keys())
        return f"<keys(...)>"

    def _resolve_values(self, args_str: str) -> Any:
        """Resolve values(map)."""
        val = self._resolve_expr(args_str.strip())
        if isinstance(val, dict):
            return list(val.values())
        return f"<values(...)>"

    def _resolve_sort(self, args_str: str) -> Any:
        """Resolve sort(list)."""
        val = self._resolve_expr(args_str.strip())
        if isinstance(val, list):
            try:
                return sorted(val)
            except TypeError:
                return val
        return f"<sort(...)>"

    def _dot_lookup(self, ctx: dict, dotted: str) -> Any:
        """Navigate a.b.c through nested dicts."""
        parts = dotted.split(".")
        current: Any = ctx
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return f"<unresolved: {dotted}>"
        return current

    def _split_top_level(self, s: str) -> List[str]:
        """Split on commas at bracket depth 0."""
        parts: list = []
        depth = 0
        current = ""
        in_str = False
        escape = False
        for ch in s:
            if escape:
                current += ch
                escape = False
                continue
            if ch == "\\":
                escape = True
                current += ch
                continue
            if ch == '"':
                in_str = not in_str
            elif not in_str:
                if ch in "({[":
                    depth += 1
                elif ch in ")}]":
                    depth -= 1
                elif ch == "," and depth == 0:
                    parts.append(current)
                    current = ""
                    continue
            current += ch
        if current.strip():
            parts.append(current)
        return parts

    def _resolve_read_terragrunt_config(self, expr: str) -> Any:
        """Attempt to parse a local file referenced by read_terragrunt_config()."""
        # Extract the path argument
        # Patterns: read_terragrunt_config("relative/path.hcl")
        #           read_terragrunt_config(find_in_parent_folders("name.hcl"))
        m = re.search(r'find_in_parent_folders\("([^"]+)"\)', expr)
        if m:
            filename = m.group(1)
            resolved = self._find_in_parents(filename)
        else:
            m = re.search(r'read_terragrunt_config\(\s*"([^"]+)"\s*\)', expr)
            if m:
                raw_path = m.group(1)
                # Resolve ${...} interpolation in the path (e.g. "${local.networking_root_dir}/...")
                if "${" in raw_path:
                    raw_path = self._resolve_string(raw_path)
                    if isinstance(raw_path, str) and ("${" in raw_path or raw_path.startswith("<")):
                        self._track_unresolved("<read_terragrunt_config(...)>")
                        return "<read_terragrunt_config(...)>"
                p = Path(raw_path)
                if not p.is_absolute():
                    p = self.resource_path / p
                resolved = str(p.resolve()) if p.resolve().is_file() else None
            else:
                self._track_unresolved("<read_terragrunt_config(...)>")
                return "<read_terragrunt_config(...)>"

        if resolved is None or not Path(resolved).is_file():
            self._track_unresolved("<read_terragrunt_config(...)>")
            return "<read_terragrunt_config(...)>"

        # Cache and parse
        if resolved in self._rtc_cache:
            return self._rtc_cache[resolved]

        try:
            parsed = Hcl2JsonParser.parse(resolved)
            # Return structure matching Terragrunt: { locals: { ... } }
            locals_raw = parsed.get("locals", [{}])
            if isinstance(locals_raw, list):
                flat: dict = {}
                for block in locals_raw:
                    if isinstance(block, dict):
                        flat.update(block)
                locals_dict = flat
            else:
                locals_dict = locals_raw if isinstance(locals_raw, dict) else {}
            # Resolve static values in the parsed locals
            resolved_locals: dict = {}
            for k, v in locals_dict.items():
                resolved_locals[k] = self.resolve_value(v)
            result = {"locals": resolved_locals}
            self._rtc_cache[resolved] = result
            return result
        except Exception:
            self._track_unresolved("<read_terragrunt_config(...)>")
            return "<read_terragrunt_config(...)>"

    def _find_in_parents(self, filename: str) -> Optional[str]:
        """Walk up from resource_path to repo_root looking for *filename*."""
        current = self.resource_path
        while current >= self.repo_root:
            candidate = current / filename
            if candidate.is_file():
                return str(candidate)
            if current == self.repo_root:
                break
            current = current.parent
        return None

    def _parse_hcl_map(self, inner: str) -> dict:
        """Parse an HCL map literal like ``key = "value"\n key2 = expr``.

        Handles multi-line values by tracking bracket depth and
        comma-separated key-value pairs on the same line.
        """
        result: dict = {}
        # Pre-process: split comma-separated key=value pairs on the same line
        # e.g. "nat_ip = null, network_tier = \"STANDARD\""
        # becomes two lines: "nat_ip = null" and "network_tier = \"STANDARD\""
        raw_lines = inner.split("\n")
        lines: list = []
        for raw_line in raw_lines:
            stripped = raw_line.strip()
            # Only attempt splitting if line has comma + key=val pattern at depth 0
            if ", " in stripped and "=" in stripped:
                parts = self._split_top_level(stripped)
                if len(parts) > 1 and all(re.match(r'\s*\w+\s*=', p) for p in parts):
                    lines.extend(parts)
                    continue
            lines.append(raw_line)
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if not line or line.startswith("#") or line.startswith("//"):
                i += 1
                continue
            m = re.match(r'([\w-]+)\s*=\s*(.*)', line)
            if not m:
                i += 1
                continue
            key = m.group(1)
            val_raw = m.group(2).strip()
            # Strip trailing comma only from the top-level value assignment
            if val_raw.endswith(","):
                val_raw = val_raw[:-1].rstrip()
            # Accumulate multi-line values by tracking bracket depth
            depth = 0
            in_str = False
            for ci, ch in enumerate(val_raw):
                if ch == '"' and (ci == 0 or val_raw[ci - 1] != '\\'):
                    in_str = not in_str
                elif not in_str:
                    if ch in "({[":
                        depth += 1
                    elif ch in ")}]":
                        depth -= 1
            # Accumulate continuation lines (do NOT strip commas — they are
            # part of the expression, e.g. merge(arg1, arg2))
            while depth > 0 and i + 1 < len(lines):
                i += 1
                next_line = lines[i]
                val_raw += "\n" + next_line
                for ci, ch in enumerate(next_line):
                    if ch == '"' and (ci == 0 or next_line[ci - 1] != '\\'):
                        in_str = not in_str
                    elif not in_str:
                        if ch in "({[":
                            depth += 1
                        elif ch in ")}]":
                            depth -= 1
            result[key] = self._resolve_expr(val_raw.strip()) if val_raw.strip() else ""
            i += 1
        return result

    def _has_placeholder(self, value: Any) -> bool:
        if isinstance(value, str):
            return value.startswith("<") or "${" in value
        if isinstance(value, dict):
            return any(self._has_placeholder(v) for v in value.values())
        if isinstance(value, list):
            return any(self._has_placeholder(v) for v in value)
        return False

    def _track_unresolved(self, token: str) -> None:
        clean = token.strip("<>")
        if clean not in self.unresolved:
            self.unresolved.append(clean)


# ─────────────────────────────────────────────────────────────────────────────
# DeepMerger — Terragrunt-compatible deep merge
# ─────────────────────────────────────────────────────────────────────────────

class DeepMerger:
    """Recursive deep merge matching Terragrunt's merge_strategy='deep' semantics.

    - Maps: recursively merge (resource keys override template keys at each level)
    - Lists: resource list **replaces** template list entirely
    - Scalars: resource value overrides template value
    """

    @staticmethod
    def merge(base: dict, override: dict) -> dict:
        result = dict(base)
        for key, val in override.items():
            if (
                key in result
                and isinstance(result[key], dict)
                and isinstance(val, dict)
            ):
                result[key] = DeepMerger.merge(result[key], val)
            else:
                result[key] = val
        return result


# ─────────────────────────────────────────────────────────────────────────────
# FullConfigRenderer — orchestrator for --full mode
# ─────────────────────────────────────────────────────────────────────────────

class FullConfigRenderer:
    """Orchestrates the 3-stage pipeline for full config rendering."""

    def __init__(self, resource_path: Path, repo_root: Path):
        self.resource_path = resource_path
        self.repo_root = repo_root

    def render(self) -> dict:
        """Return ``{terraform_source, inputs, unresolved}``."""
        # Stage 1: hierarchy merge (existing code)
        merger = HierarchyMerger(self.resource_path, self.repo_root)
        merged, derived, labels = merger.merge()
        derived["resource_name"] = self.resource_path.name

        # Stage 2: parse resource terragrunt.hcl via hcl2json
        resource_hcl = self.resource_path / "terragrunt.hcl"
        if not resource_hcl.is_file():
            raise FileNotFoundError(f"No terragrunt.hcl found at {self.resource_path}")
        resource_parsed = Hcl2JsonParser.parse(str(resource_hcl))
        resource_blocks = Hcl2JsonParser.extract_blocks(resource_parsed)

        # Identify template
        include_resolver = IncludeResolver(
            resource_blocks["include"], self.resource_path, self.repo_root,
        )
        template_path = include_resolver.find_template()

        # Build dependency resolver from resource (and template if present)
        dep_resolver = DependencyResolver(resource_blocks["dependency"])

        # Build expression resolver
        expr_resolver = ExpressionResolver(
            merged, derived, labels, dep_resolver, self.resource_path,
            repo_root=self.repo_root,
        )

        # Resolve exposed includes (compute_common, secrets_common, etc.)
        exposed = include_resolver.find_exposed_includes()
        for inc_name, inc_path in exposed.items():
            try:
                inc_parsed = Hcl2JsonParser.parse(str(inc_path))
                inc_blocks = Hcl2JsonParser.extract_blocks(inc_parsed)
                inc_expr = ExpressionResolver(
                    merged, derived, labels, dep_resolver, self.resource_path,
                    repo_root=self.repo_root,
                )
                inc_locals = inc_expr.resolve_locals(inc_blocks["locals"])
                expr_resolver.extra_includes[inc_name] = inc_locals
            except Exception:
                pass  # skip includes that fail to parse

        # Resolve resource locals
        resource_locals = expr_resolver.resolve_locals(resource_blocks["locals"])
        expr_resolver.set_locals_context(resource_locals)

        # Parse and resolve template if found
        template_inputs: dict = {}
        terraform_source = ""
        if template_path:
            template_parsed = Hcl2JsonParser.parse(str(template_path))
            template_blocks = Hcl2JsonParser.extract_blocks(template_parsed)

            # Template dependencies may add extra mocks and paths
            tmpl_dep_resolver = DependencyResolver(template_blocks["dependency"])
            for name, mock in tmpl_dep_resolver.get_all_mocks().items():
                if name not in dep_resolver.mocks:
                    dep_resolver.mocks[name] = mock
            for name, path in tmpl_dep_resolver.paths.items():
                if name not in dep_resolver.paths:
                    dep_resolver.paths[name] = path

            # Resolve template locals (template has its own locals context)
            tmpl_expr_resolver = ExpressionResolver(
                merged, derived, labels, dep_resolver, self.resource_path,
                repo_root=self.repo_root,
            )
            # Pre-seed template locals with hierarchy values that templates
            # normally obtain via read_terragrunt_config(common.hcl).
            tmpl_seed = {
                "common_vars": {"locals": merged},
                "module_versions": derived.get("module_versions", {}),
            }
            template_locals = tmpl_expr_resolver.resolve_locals(
                template_blocks["locals"], seed=tmpl_seed,
            )
            tmpl_expr_resolver.set_locals_context(template_locals)

            # Resolve template inputs
            template_inputs = tmpl_expr_resolver.resolve_inputs(template_blocks["inputs"])

            # Extract terraform source
            terraform_source = self._extract_source(
                template_blocks["terraform"], template_locals, derived,
            )
            # Collect unresolved from template
            for u in tmpl_expr_resolver.unresolved:
                expr_resolver._track_unresolved(u)

        # If no template source, check resource's own terraform block
        if not terraform_source:
            terraform_source = self._extract_source(
                resource_blocks["terraform"], resource_locals, derived,
            )

        # Resolve resource inputs
        resource_inputs = expr_resolver.resolve_inputs(resource_blocks["inputs"])

        # Stage 3: deep merge template ← resource
        final_inputs = DeepMerger.merge(template_inputs, resource_inputs)

        # Build source tracking: which file each input key came from
        sources: dict = {}
        tmpl_rel = ""
        res_rel = str(resource_hcl.relative_to(self.repo_root))
        if template_path:
            try:
                tmpl_rel = str(template_path.relative_to(self.repo_root))
            except ValueError:
                tmpl_rel = str(template_path)
        for k in final_inputs:
            if k in resource_inputs:
                sources[k] = res_rel
            elif k in template_inputs:
                sources[k] = tmpl_rel

        return {
            "terraform_source": terraform_source,
            "inputs": final_inputs,
            "unresolved": sorted(set(expr_resolver.unresolved)),
            "sources": sources,
        }

    def _extract_source(self, tf_blocks: list, locals_ctx: dict, derived: dict) -> str:
        """Extract and resolve terraform source URL."""
        for block in tf_blocks:
            if not isinstance(block, dict):
                continue
            source = block.get("source", "")
            if not source:
                continue
            # Resolve ${local.module_versions.X}
            def _repl_local(m: re.Match) -> str:
                ref = m.group(1).strip()
                parts = ref.split(".")
                if parts[0] == "local":
                    val = locals_ctx
                    for p in parts[1:]:
                        if isinstance(val, dict) and p in val:
                            val = val[p]
                        else:
                            return m.group(0)
                    return str(val)
                return m.group(0)

            source = re.sub(r"\$\{([^}]+)}", _repl_local, source)

            # Also resolve include.base.locals.module_versions.X
            def _repl_include(m: re.Match) -> str:
                ref = m.group(1).strip()
                if ref.startswith("include.base.locals."):
                    dotted = ref[len("include.base.locals."):]
                    parts = dotted.split(".")
                    val: Any = {
                        "module_versions": derived.get("module_versions", {}),
                    }
                    for p in parts:
                        if isinstance(val, dict) and p in val:
                            val = val[p]
                        else:
                            return m.group(0)
                    return str(val)
                return m.group(0)

            source = re.sub(r"\$\{([^}]+)}", _repl_include, source)
            return source
        return ""


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Render the merged Terragrunt hierarchy config for a resource path.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument(
        "resource_path",
        nargs="?",
        default=".",
        help="Path to a resource directory (default: current directory)",
    )
    p.add_argument(
        "-f", "--format",
        choices=["json", "yaml", "table"],
        default="json",
        dest="fmt",
        help="Output format (default: json)",
    )
    p.add_argument(
        "-k", "--key",
        action="append",
        dest="keys",
        metavar="KEY",
        help="Filter output to specific key(s) — repeatable",
    )
    p.add_argument(
        "--show-sources",
        action="store_true",
        help="Include which hierarchy file each value originated from",
    )
    p.add_argument(
        "--show-labels",
        action="store_true",
        help="Show only the computed standard_labels",
    )
    p.add_argument(
        "--show-metadata",
        action="store_true",
        help="Show only the metadata dict from inputs (--full mode only)",
    )
    p.add_argument(
        "--full",
        action="store_true",
        help="Render full config: template defaults deep-merged with resource overrides, "
             "expressions resolved against hierarchy. Requires hcl2json on PATH.",
    )
    p.add_argument(
        "--no-colour", "--no-color",
        action="store_true",
        dest="no_colour",
        help="Disable coloured output (colours are auto-detected by default)",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()

    if args.no_colour:
        OutputFormatter._no_colour = True

    # resolve resource path
    rp = Path(args.resource_path)
    if not rp.is_absolute():
        rp = Path.cwd() / rp
    rp = rp.resolve()
    if not rp.is_dir():
        print(f"Error: resource path is not a directory: {rp}", file=sys.stderr)
        return 1

    # find repo root
    try:
        repo_root = find_repo_root(rp)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    # sanity check: path must be inside live/ hierarchy
    try:
        rel = rp.relative_to(repo_root)
    except ValueError:
        rel = Path("")
    if rel == Path("") or rel == Path(".") or not str(rel).startswith("live"):
        print(
            "Error: path must be inside the live/ hierarchy, e.g.:\n"
            "  live/non-production/development/platform/dp-dev-01/europe-west2/gke/cluster-01\n"
            "\n"
            f"Got: {rp.relative_to(repo_root) if rp != repo_root else '(repo root)'}",
            file=sys.stderr,
        )
        return 1

    # ── full mode ────────────────────────────────────────────────────────────
    if args.full:
        if not Hcl2JsonParser.is_available():
            print(
                "Error: hcl2json not found on PATH.\n"
                "Install: go install github.com/tmccombs/hcl2json@latest\n"
                "     or: download from https://github.com/tmccombs/hcl2json/releases",
                file=sys.stderr,
            )
            return 1
        try:
            renderer = FullConfigRenderer(rp, repo_root)
            result = renderer.render()
        except (FileNotFoundError, RuntimeError) as exc:
            print(f"Error: {exc}", file=sys.stderr)
            return 1

        output = dict(result)
        full_sources = output.pop("sources", {})

        # Strip sources from default output unless requested
        if not args.show_sources:
            full_sources = {}

        # show metadata only
        if args.show_metadata:
            output = {"metadata": output.get("inputs", {}).get("metadata", {})}

        # filter keys (applies to inputs sub-dict)
        elif args.keys:
            filtered_inputs = {
                k: v for k, v in output.get("inputs", {}).items()
                if k in args.keys
            }
            output = {
                "terraform_source": output["terraform_source"],
                "inputs": filtered_inputs,
                "unresolved": output.get("unresolved", []),
            }
            if full_sources:
                full_sources = {k: v for k, v in full_sources.items() if k in args.keys}

        if full_sources:
            output["sources"] = full_sources

        if args.fmt == "json":
            print(OutputFormatter.as_json(output))
        elif args.fmt == "yaml":
            print(OutputFormatter.as_yaml(output))
        elif args.fmt == "table":
            sources_for_table = output.pop("sources", None) if args.show_sources else None
            print(OutputFormatter.as_table(output, sources=sources_for_table))
        return 0

    # ── hierarchy-only mode (existing behaviour) ─────────────────────────────

    # merge hierarchy
    merger = HierarchyMerger(rp, repo_root)
    try:
        merged, derived, labels = merger.merge()
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    # add resource_name to derived (depends on resource_path, not merged)
    derived["resource_name"] = rp.name

    # ── build output ─────────────────────────────────────────────────────────
    if args.show_labels:
        output = {"standard_labels": labels}
    else:
        output: dict = {"merged": merged, "derived": derived, "standard_labels": labels}
        if args.show_sources:
            # shorten paths to relative
            sources = {}
            for k, v in merger.get_sources().items():
                try:
                    sources[k] = str(Path(v).relative_to(repo_root))
                except ValueError:
                    sources[k] = v
            output["sources"] = sources

    # ── filter keys ──────────────────────────────────────────────────────────
    if args.keys and not args.show_labels:
        filtered: dict = {}
        all_data = {**merged, **derived}
        for k in args.keys:
            if k in all_data:
                filtered[k] = all_data[k]
            elif k == "standard_labels":
                filtered[k] = labels
        if args.show_sources:
            sources = {
                k: v for k, v in output.get("sources", {}).items()
                if k in args.keys
            }
            if sources:
                filtered["sources"] = sources
        output = filtered

    # ── render ───────────────────────────────────────────────────────────────
    if args.fmt == "json":
        print(OutputFormatter.as_json(output))
    elif args.fmt == "yaml":
        print(OutputFormatter.as_yaml(output))
    elif args.fmt == "table":
        sources = output.pop("sources", None) if args.show_sources else None
        print(OutputFormatter.as_table(output, sources=sources))

    return 0


if __name__ == "__main__":
    sys.exit(main())
