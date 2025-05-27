#!/usr/bin/env python3
"""
Parse Terraform/OpenTofu plan output and convert to structured JSON
Removes ANSI colors and timestamps, extracts resource changes
"""

import re
import json
import sys
from typing import Dict, List, Any
from datetime import datetime, timezone

def strip_ansi_colors(text: str) -> str:
    """Remove ANSI color codes from text"""
    ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')
    return ansi_escape.sub('', text)

def parse_resource_change(lines: List[str], start_idx: int) -> Dict[str, Any]:
    """Parse a single resource change block"""
    resource_info = {
        "action": None,
        "resource_type": None,
        "resource_name": None,
        "attributes": {}
    }

    # Parse the resource header line
    header_line = lines[start_idx].strip()

    # Extract action (+ create, ~ update, - destroy, etc.)
    if header_line.startswith("+ "):
        resource_info["action"] = "create"
        header_line = header_line[2:]
    elif header_line.startswith("~ "):
        resource_info["action"] = "update"
        header_line = header_line[2:]
    elif header_line.startswith("- "):
        resource_info["action"] = "destroy"
        header_line = header_line[2:]
    elif header_line.startswith("-/+ "):
        resource_info["action"] = "replace"
        header_line = header_line[4:]

    # Extract resource type and name
    resource_match = re.match(r'resource "([^"]+)" "([^"]+)"', header_line)
    if resource_match:
        resource_info["resource_type"] = resource_match.group(1)
        resource_info["resource_name"] = resource_match.group(2)

    # Parse attributes
    i = start_idx + 1
    while i < len(lines) and not lines[i].strip().startswith("+ resource "):
        line = lines[i].strip()
        if line.startswith("+ ") or line.startswith("~ ") or line.startswith("- "):
            # Parse attribute line
            attr_line = line[2:].strip()
            if " = " in attr_line:
                key, value = attr_line.split(" = ", 1)
                key = key.strip()
                value = value.strip()

                # Clean up value formatting
                if value == "(known after apply)":
                    value = None
                elif value.startswith('"') and value.endswith('"'):
                    value = value[1:-1]  # Remove quotes
                elif value == "true":
                    value = True
                elif value == "false":
                    value = False
                elif value.isdigit():
                    value = int(value)
                elif value.startswith("{") or value.startswith("["):
                    # Handle complex structures - keep as string for now
                    pass

                resource_info["attributes"][key] = value
        i += 1

    return resource_info

def parse_plan_output(raw_output: str) -> Dict[str, Any]:
    """Parse the complete plan output"""
    # Strip ANSI colors and split into lines
    clean_output = strip_ansi_colors(raw_output)
    lines = clean_output.split('\n')

    plan_data = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "summary": {
            "to_create": 0,
            "to_update": 0,
            "to_destroy": 0,
            "to_replace": 0
        },
        "resources": [],
        "data_sources": [],
        "outputs": {}
    }

    i = 0
    while i < len(lines):
        line = lines[i].strip()

        # Remove timestamp prefix if present
        if re.match(r'^\d{2}:\d{2}:\d{2}\.\d{3} STDOUT tofu:', line):
            line = re.sub(r'^\d{2}:\d{2}:\d{2}\.\d{3} STDOUT tofu:\s*', '', line)

        # Parse resource changes
        if ("+ resource " in line or "~ resource " in line or
            "- resource " in line or "-/+ resource " in line):
            resource = parse_resource_change(lines, i)
            if resource["resource_type"]:  # Only add if we successfully parsed it
                plan_data["resources"].append(resource)

            # Update summary
            action = resource["action"]
            if action == "create":
                plan_data["summary"]["to_create"] += 1
            elif action == "update":
                plan_data["summary"]["to_update"] += 1
            elif action == "destroy":
                plan_data["summary"]["to_destroy"] += 1
            elif action == "replace":
                plan_data["summary"]["to_replace"] += 1

        # Parse data source reads
        elif "data." in line and "Read complete" in line:
            data_match = re.search(r'data\.([^:]+):\s*Read complete', line)
            if data_match:
                plan_data["data_sources"].append({
                    "name": data_match.group(1),
                    "status": "read_complete"
                })

        i += 1

    return plan_data

def main():
    """Main function to process stdin or file input"""
    if len(sys.argv) > 1:
        # Read from file
        with open(sys.argv[1], 'r') as f:
            raw_input = f.read()
    else:
        # Read from stdin
        raw_input = sys.stdin.read()

    # Parse the plan output
    parsed_data = parse_plan_output(raw_input)

    # Output as formatted JSON
    print(json.dumps(parsed_data, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
