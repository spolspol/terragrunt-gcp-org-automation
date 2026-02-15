#!/usr/bin/env python3
import argparse
import os
import sys

def update_definitions(args):
    filepath = '.github/workflow-config/resource-definitions.yml'
    print(f"Updating {filepath}...")

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    if f"  {args.name}:" in content:
        print(f"Resource {args.name} already exists in definitions.")
        return

    # Check for duplicate emoji
    if f'emoji: "{args.emoji}"' in content:
        print(f"Warning: Emoji '{args.emoji}' is already used by another resource.")
        print("Please choose a unique emoji to avoid confusion in logs and summaries.")
        sys.exit(1)

    # Prepare new resource block
    new_block = [
        f"",
        f"  # {args.description}",
        f"  {args.name}:",
        f"    dependencies: [{', '.join(args.dependencies.split(',')) if args.dependencies else ''}]",
        f"    path_pattern: \"{args.path_pattern}\"",
        f"    template_path: \"{args.template_path}\"",
        f"    emoji: \"{args.emoji}\"",
        f"    name: \"{args.display_name}\"",
        f"    description: \"{args.description}\"",
    ]

    with open(filepath, 'a', encoding='utf-8') as f:
        f.write('\n'.join(new_block) + '\n')
    print("Definitions updated.")

def update_workflow(args):
    filepath = '.github/workflows.disabled/terragrunt-main-engine.yml'
    print(f"Updating {filepath}...")

    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    # Check if job already exists
    if any(line.strip() == f"{args.name}:" for line in lines):
        print(f"Job {args.name} already exists in workflow.")
        return

    # Generate new job YAML
    deps = [f"{d}" for d in args.dependencies.split(',')] if args.dependencies else []
    needs_list = ['detect-changes'] + deps
    needs_str = ', '.join(needs_list)

    new_job = [
        f"",
        f"  # {args.description}",
        f"  {args.name}:",
        f"    name: \"${{{{ needs.detect-changes.outputs.action_name }}}} ${{{{ fromJson(needs.detect-changes.outputs.emojis || '{{}}')['{args.name}'] }}}} ${{{{ fromJson(needs.detect-changes.outputs.names || '{{}}')['{args.name}'] }}}}\"",
        f"    needs: [{needs_str}]",
        f"    if: always() && !contains(needs.*.result, 'failure') && !contains(needs.*.result, 'cancelled') && fromJson(needs.detect-changes.outputs.changes || '{{}}').{args.name} != null",
        f"    uses: ./.github/workflows/terragrunt-reusable.yaml",
        f"    with:",
        f"      mode: ${{{{ github.event_name == 'push' && 'apply' || 'validate' }}}}",
        f"      resource_type: ${{{{ fromJson(needs.detect-changes.outputs.changes || '{{}}')['{args.name}'].config.id }}}}",
        f"      resource_paths: ${{{{ toJson(fromJson(needs.detect-changes.outputs.changes || '{{}}').{args.name}.paths) }}}}",
        f"      template_path: ${{{{ fromJson(needs.detect-changes.outputs.changes || '{{}}').{args.name}.config.template_path }}}}",
        f"      resource_emoji: ${{{{ fromJson(needs.detect-changes.outputs.changes || '{{}}').{args.name}.config.emoji }}}}",
        f"      resource_description: ${{{{ fromJson(needs.detect-changes.outputs.changes || '{{}}').{args.name}.config.description }}}}",
        f"    secrets: inherit",
    ]

    # Find insertion point (before merge-gate)
    insert_idx = -1
    merge_gate_idx = -1

    for i, line in enumerate(lines):
        if line.strip() == 'merge-gate:':
            merge_gate_idx = i
            insert_idx = i
            break

    if insert_idx == -1:
        print("Could not find merge-gate job. Appending to end.")
        insert_idx = len(lines)

    # Insert new job
    lines[insert_idx:insert_idx] = [line + '\n' for line in new_job]

    # Update merge-gate dependencies
    # We need to find the 'needs:' block inside merge-gate and append the new resource
    # Since we inserted lines, merge_gate_idx shifted by len(new_job)
    merge_gate_idx += len(new_job)

    needs_start_idx = -1
    for i in range(merge_gate_idx, len(lines)):
        if lines[i].strip() == 'needs:':
            needs_start_idx = i
            break

    if needs_start_idx != -1:
        # Find the end of the needs block (next line with same indentation as needs or less)
        # Actually, needs is a list, usually indented.
        # We look for the last item in the list
        last_item_idx = -1
        for i in range(needs_start_idx + 1, len(lines)):
            if lines[i].strip().startswith('- '):
                last_item_idx = i
            elif lines[i].strip() and not lines[i].startswith(' ' * 6): # Assuming 6 spaces indentation for list items
                break

        if last_item_idx != -1:
            lines.insert(last_item_idx + 1, f"      - {args.name}\n")
            print(f"Added {args.name} to merge-gate dependencies.")
        else:
            print("Could not find end of merge-gate needs list.")

    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Workflow updated.")

def main():
    parser = argparse.ArgumentParser(description='Add new resource support to workflow')
    parser.add_argument('--name', required=True, help='Resource name (kebab-case)')
    parser.add_argument('--display-name', help='Human readable name (defaults to Title Case of name)')
    parser.add_argument('--description', required=True, help='Resource description')
    parser.add_argument('--emoji', default='✨', help='Emoji for the resource')
    parser.add_argument('--dependencies', default='', help='Comma-separated list of dependencies')
    parser.add_argument('--path-pattern', help='Path pattern (default: live/**/<name>/**)')
    parser.add_argument('--template-path', help='Template path (default: _common/templates/<name>)')

    args = parser.parse_args()

    if not args.display_name:
        args.display_name = args.name.replace('-', ' ').title()

    if not args.path_pattern:
        args.path_pattern = f"live/**/{args.name}/**"
    if not args.template_path:
        args.template_path = f"_common/templates/{args.name}"

    update_definitions(args)
    update_workflow(args)
    print(f"Successfully added support for {args.name}!")

if __name__ == '__main__':
    main()
