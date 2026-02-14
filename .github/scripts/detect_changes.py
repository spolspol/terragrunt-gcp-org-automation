#!/usr/bin/env python3
import os
import sys
import json
import yaml
import subprocess
import re
import argparse
from typing import Dict, List, Set, Any

def load_resource_definitions(path: str) -> Dict[str, Any]:
    with open(path, 'r') as f:
        return yaml.safe_load(f)

def get_changed_files(base_ref: str, head_ref: str) -> List[str]:
    """Get list of changed files between two refs."""
    # Validate base_ref is an ancestor of head_ref (handles force push where old commit is orphaned)
    try:
        subprocess.check_output(
            ['git', 'merge-base', '--is-ancestor', base_ref, head_ref],
            stderr=subprocess.DEVNULL
        )
    except subprocess.CalledProcessError:
        print(f"Warning: base-ref '{base_ref}' is not an ancestor of HEAD (possibly force push), using HEAD~1", file=sys.stderr)
        base_ref = 'HEAD~1'

    cmd = ['git', 'diff', '--name-only', base_ref, head_ref]
    try:
        output = subprocess.check_output(cmd, text=True)
        return [line.strip() for line in output.splitlines() if line.strip()]
    except subprocess.CalledProcessError as e:
        print(f"Error getting changed files: {e}", file=sys.stderr)
        return []

def match_pattern(file_path: str, patterns: Any) -> bool:
    """Check if file matches any of the patterns."""
    if not patterns:
        return False

    if isinstance(patterns, str):
        patterns = [patterns]

    for pattern in patterns:
        # Convert glob pattern to regex
        # This is a simplified conversion, might need robustness for complex globs
        # escape dots, replace ** with placeholder, * with [^/]*, then placeholder with .*
        regex = pattern.replace('.', r'\.').replace('**', '__GLOBSTAR__').replace('*', r'[^/]*').replace('__GLOBSTAR__', '.*')

        if re.match(f"^{regex}$", file_path):
            return True
    return False

def get_affected_resources(changed_files: List[str], definitions: Dict[str, Any]) -> Set[str]:
    affected = set()
    resources = definitions.get('resources', {})

    for file_path in changed_files:
        for name, config in resources.items():
            # Check exclusions first
            if match_pattern(file_path, config.get('exclude_pattern')):
                continue

            # Check inclusions
            if match_pattern(file_path, config.get('path_pattern')):
                affected.add(name)

    return affected

def resolve_dependencies(affected: Set[str], definitions: Dict[str, Any]) -> List[str]:
    """
    Sort affected resources based on dependencies.
    Returns a list of resource names in execution order.
    """
    resources = definitions.get('resources', {})

    # Topological sort
    result = []
    visited = set()
    temp_visited = set()

    def visit(node):
        if node in temp_visited:
            print(f"Warning: Circular dependency detected involving {node}", file=sys.stderr)
            return
        if node in visited:
            return
        if node not in affected:
            return

        temp_visited.add(node)

        # Visit dependencies first
        deps = resources.get(node, {}).get('dependencies', [])
        for dep in deps:
            visit(dep)

        temp_visited.remove(node)
        visited.add(node)
        result.append(node)

    for resource in affected:
        visit(resource)

    return result

def expand_resource_paths(resource_name: str, config: Dict[str, Any]) -> Set[str]:
    """
    Find all instances of a resource type by scanning the filesystem
    and matching against path_pattern and exclude_pattern.
    """
    found_paths = set()

    # We assume all resources are under 'live' directory as per convention
    # This optimization avoids scanning the entire repo
    search_root = 'live'
    if not os.path.exists(search_root):
        return found_paths

    print(f"Expanding {resource_name} (scanning {search_root})...", file=sys.stderr)

    # Walk the filesystem to find terragrunt.hcl files
    for root, dirs, files in os.walk(search_root):
        # Skip Terragrunt cache directories (contain module source, not real configs)
        dirs[:] = [d for d in dirs if d != '.terragrunt-cache']
        if 'terragrunt.hcl' in files:
            # Check if this directory matches the resource configuration
            # We use the relative path from repo root for matching
            rel_path = os.path.relpath(root, os.getcwd())

            # Check exclusions first
            if match_pattern(os.path.join(rel_path, 'terragrunt.hcl'), config.get('exclude_pattern')):
                continue

            # Ignore example resources
            if os.path.basename(root).startswith('example-'):
                continue


            # Check inclusions
            # We append a trailing slash to match directory patterns like "live/**/vpc-network/**"
            # or we match the path itself.
            # The match_pattern function expects the file path.
            # Our patterns in resource-definitions.yml are like "live/**/vpc-network/**"
            # If we have "live/dev/vpc-network", it matches.

            # because the patterns are designed to match file paths (e.g. including /**)
            check_path = os.path.join(rel_path, 'terragrunt.hcl')
            if match_pattern(check_path, config.get('path_pattern')):
                found_paths.add(rel_path)



    return found_paths

def find_resource_root(file_path: str) -> str:
    """Find the directory containing terragrunt.hcl for a given file."""
    current = os.path.dirname(os.path.abspath(file_path))
    # Stop at git root or some reasonable limit
    while len(current) > 1:
        if os.path.exists(os.path.join(current, 'terragrunt.hcl')):
            return current
        current = os.path.dirname(current)
    return None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--definitions', required=True, help='Path to resource-definitions.yml')
    parser.add_argument('--base-ref', required=True, help='Base git ref')
    parser.add_argument('--head-ref', required=True, help='Head git ref')
    args = parser.parse_args()

    definitions = load_resource_definitions(args.definitions)
    changed_files = get_changed_files(args.base_ref, args.head_ref)



    # Group changed files by resource type
    resources_map = {} # Type -> Set[Paths]
    deleted_resources_map = {} # Type -> Set[Paths]

    # Track which resources need full expansion due to template changes
    resources_to_expand = set()

    for file_path in changed_files:
        # Check for template changes
        for name, config in definitions.get('resources', {}).items():
            template_path = config.get('template_path')
            if template_path and file_path.startswith(template_path):
                resources_to_expand.add(name)

        # Find which resource type this file belongs to (direct changes)
        matched_type = None
        for name, config in definitions.get('resources', {}).items():
            if match_pattern(file_path, config.get('exclude_pattern')):
                continue
            if match_pattern(file_path, config.get('path_pattern')):
                matched_type = name
                break

        if matched_type:
            # Find the specific instance directory (where terragrunt.hcl lives)
            if os.path.exists(file_path):
                root = find_resource_root(file_path)
                if root:
                    # Check if it's an example resource
                    if os.path.basename(root).startswith('example-'):
                        continue

                    # Make path relative to repo root
                    rel_root = os.path.relpath(root, os.getcwd())

                    if matched_type not in resources_map:
                        resources_map[matched_type] = set()
                    resources_map[matched_type].add(rel_root)
            else:
                # Handle deleted files
                if os.path.basename(file_path) == 'terragrunt.hcl':
                    # The terragrunt.hcl file itself was deleted - infer root from path
                    # IMPORTANT: Check this FIRST before find_resource_root() which would
                    # walk up and find a parent's terragrunt.hcl (e.g., for iam-bindings)
                    rel_root = os.path.dirname(file_path)

                    # Check if it was an example resource
                    if os.path.basename(rel_root).startswith('example-'):
                        continue

                    if matched_type not in deleted_resources_map:
                        deleted_resources_map[matched_type] = set()
                    deleted_resources_map[matched_type].add(rel_root)
                else:
                    # Non-terragrunt.hcl file deleted - find resource root if it exists
                    root = find_resource_root(file_path)
                    if root:
                        # Resource still exists, just a file within it was deleted
                        rel_root = os.path.relpath(root, os.getcwd())
                        if matched_type not in resources_map:
                            resources_map[matched_type] = set()
                        resources_map[matched_type].add(rel_root)

    # Expand resources that had template changes
    for r_type in resources_to_expand:
        expanded_paths = expand_resource_paths(r_type, definitions['resources'][r_type])
        if r_type not in resources_map:
            resources_map[r_type] = set()
        resources_map[r_type].update(expanded_paths)

    # Sort resource types by dependency
    affected_types = set(resources_map.keys())
    sorted_types = resolve_dependencies(affected_types, definitions)

    # Construct Output Map
    output_map = {}
    for r_type in sorted_types:
        paths = sorted(list(resources_map[r_type]))
        if paths:
            # Include resource type as 'id' in config for workflow conditionals
            config = dict(definitions['resources'][r_type])
            config['id'] = r_type
            output_map[r_type] = {
                "paths": paths,
                "config": config
            }

    # Generate Summary
    generate_summary(output_map, deleted_resources_map, definitions)

    # Output changes and emojis to GITHUB_OUTPUT
    write_github_output("changes", json.dumps(output_map))

    # Generate emojis map for all resources
    emojis_map = {}
    for name, config in definitions.get('resources', {}).items():
        emojis_map[name] = config.get('emoji', '')

    write_github_output("emojis", json.dumps(emojis_map))

    # Generate names map for all resources
    names_map = {}
    for name, config in definitions.get('resources', {}).items():
        names_map[name] = config.get('name', '')

    write_github_output("names", json.dumps(names_map))

    # Print for debugging (optional, but good for logs)
    print(json.dumps(output_map))

def write_github_output(key: str, value: str):
    """Write output to GITHUB_OUTPUT."""
    github_output = os.environ.get('GITHUB_OUTPUT')
    if github_output:
        try:
            with open(github_output, 'a', encoding='utf-8') as f:
                # Use delimiter for multiline strings to be safe, though JSON is single line usually
                delimiter = f"ghodelimiter_{os.urandom(16).hex()}"
                f.write(f"{key}<<{delimiter}\n{value}\n{delimiter}\n")
        except Exception as e:
            print(f"Warning: Could not write to GITHUB_OUTPUT: {e}", file=sys.stderr)
    else:
        # Fallback for local testing
        print(f"[GITHUB_OUTPUT] {key}={value}", file=sys.stderr)


def generate_summary(output_map: Dict[str, Any], deleted_map: Dict[str, Set[str]], definitions: Dict[str, Any]):
    """Generate human-readable summary for logs and GitHub Actions."""
    if not output_map and not deleted_map:
        summary = "No infrastructure changes detected."
        print(summary, file=sys.stderr)
        write_github_summary(f"### {summary}")
        return

    # Text Summary for Logs
    print("\n" + "="*50, file=sys.stderr)
    print("DETECTED INFRASTRUCTURE CHANGES", file=sys.stderr)
    print("="*50, file=sys.stderr)

    if output_map:
        print("Modified/Created Resources:", file=sys.stderr)
        for r_type, data in output_map.items():
            emoji = data['config'].get('emoji', '')
            count = len(data['paths'])
            print(f"{emoji} {r_type} ({count} resources):", file=sys.stderr)
            for path in data['paths']:
                print(f"  - {path}", file=sys.stderr)

    if deleted_map:
        print("\nDeleted Resources:", file=sys.stderr)
        for r_type, paths in deleted_map.items():
            config = definitions['resources'].get(r_type, {})
            emoji = config.get('emoji', '')
            count = len(paths)
            print(f"{emoji} {r_type} ({count} resources):", file=sys.stderr)
            for path in paths:
                print(f"  - {path}", file=sys.stderr)

    print("="*50 + "\n", file=sys.stderr)

    # Markdown Summary for GitHub Actions
    md_lines = ["### Infrastructure Changes Detected", ""]

    if output_map:
        md_lines.append("#### Modified / Created")
        md_lines.append("| Resource Type | Count | Paths |")
        md_lines.append("| :--- | :---: | :--- |")

        for r_type, data in output_map.items():
            emoji = data['config'].get('emoji', '')
            count = len(data['paths'])
            # Limit paths in table to avoid huge outputs
            paths_display = "<br>".join([f"`{p}`" for p in data['paths'][:5]])
            if count > 5:
                paths_display += f"<br>...and {count - 5} more"

            md_lines.append(f"| {emoji} `{r_type}` | {count} | {paths_display} |")

        md_lines.append("")

    if deleted_map:
        md_lines.append("#### Deleted")
        md_lines.append("| Resource Type | Count | Paths |")
        md_lines.append("| :--- | :---: | :--- |")

        for r_type, paths in deleted_map.items():
            config = definitions['resources'].get(r_type, {})
            emoji = config.get('emoji', '')
            paths_list = sorted(list(paths))
            count = len(paths_list)

            paths_display = "<br>".join([f"`{p}`" for p in paths_list[:5]])
            if count > 5:
                paths_display += f"<br>...and {count - 5} more"

            md_lines.append(f"| {emoji} `{r_type}` | {count} | {paths_display} |")

    write_github_summary("\n".join(md_lines))

def write_github_summary(content: str):
    """Write content to GITHUB_STEP_SUMMARY if available."""
    summary_file = os.environ.get('GITHUB_STEP_SUMMARY')
    if summary_file:
        try:
            with open(summary_file, 'a', encoding='utf-8') as f:
                f.write(content + "\n")

        except Exception as e:
            print(f"Warning: Could not write to GITHUB_STEP_SUMMARY: {e}", file=sys.stderr)



if __name__ == "__main__":
    main()
