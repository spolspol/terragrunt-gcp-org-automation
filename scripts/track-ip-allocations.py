#!/usr/bin/env python3
"""
IP Allocation Tracking Script
Tracks and validates IP allocations across the infrastructure
"""

import os
import sys
import json
import yaml
import ipaddress
from pathlib import Path
from typing import Dict, List, Set, Tuple
from collections import defaultdict

class IPAllocationTracker:
    """Track and validate IP allocations across Terragrunt configurations"""
    
    def __init__(self, repo_root: str):
        self.repo_root = Path(repo_root)
        self.allocations = defaultdict(list)
        self.conflicts = []
        
    def scan_terragrunt_files(self):
        """Scan all terragrunt.hcl files for IP allocations"""
        for hcl_file in self.repo_root.rglob("terragrunt.hcl"):
            self._parse_hcl_file(hcl_file)
            
    def _parse_hcl_file(self, file_path: Path):
        """Parse a terragrunt.hcl file for IP addresses and CIDR blocks"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()
                
            # Extract IP addresses and CIDR blocks
            import re
            
            # Pattern for IP addresses and CIDR blocks
            ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b'
            
            for match in re.finditer(ip_pattern, content):
                ip_str = match.group()
                
                # Skip mock IPs and examples
                if ip_str.startswith(('1.2.3.', '0.0.0.0', '255.255.255.')):
                    continue
                    
                # Determine the context
                context = self._get_context(content, match.start())
                
                # Store the allocation
                self.allocations[ip_str].append({
                    'file': str(file_path.relative_to(self.repo_root)),
                    'context': context,
                    'line': content[:match.start()].count('\n') + 1
                })
                
        except Exception as e:
            print(f"Error parsing {file_path}: {e}", file=sys.stderr)
            
    def _get_context(self, content: str, position: int) -> str:
        """Get the context around an IP address match"""
        # Find the line containing the match
        lines = content.split('\n')
        current_pos = 0
        
        for i, line in enumerate(lines):
            if current_pos <= position < current_pos + len(line) + 1:
                # Return the variable or key name if found
                if '=' in line:
                    return line.split('=')[0].strip()
                elif ':' in line:
                    return line.split(':')[0].strip()
                else:
                    return line.strip()[:50]  # First 50 chars of the line
            current_pos += len(line) + 1
            
        return "unknown"
        
    def check_overlaps(self):
        """Check for overlapping CIDR blocks"""
        networks = []
        
        for ip_str, locations in self.allocations.items():
            if '/' in ip_str:  # It's a CIDR block
                try:
                    network = ipaddress.ip_network(ip_str, strict=False)
                    networks.append((network, ip_str, locations))
                except ValueError:
                    continue
                    
        # Check for overlaps
        for i, (net1, str1, loc1) in enumerate(networks):
            for net2, str2, loc2 in networks[i+1:]:
                if net1.overlaps(net2) and str1 != str2:
                    self.conflicts.append({
                        'type': 'overlap',
                        'network1': str1,
                        'network2': str2,
                        'locations1': loc1,
                        'locations2': loc2
                    })
                    
    def generate_report(self) -> Dict:
        """Generate an IP allocation report"""
        report = {
            'summary': {
                'total_allocations': len(self.allocations),
                'total_conflicts': len(self.conflicts),
                'cidr_blocks': sum(1 for ip in self.allocations if '/' in ip),
                'individual_ips': sum(1 for ip in self.allocations if '/' not in ip)
            },
            'allocations': {},
            'conflicts': self.conflicts
        }
        
        # Organize allocations by type
        for ip_str, locations in sorted(self.allocations.items()):
            ip_type = 'cidr' if '/' in ip_str else 'ip'
            
            if ip_type not in report['allocations']:
                report['allocations'][ip_type] = {}
                
            report['allocations'][ip_type][ip_str] = [
                {
                    'file': loc['file'],
                    'line': loc['line'],
                    'context': loc['context']
                }
                for loc in locations
            ]
            
        return report
        
    def print_report(self, report: Dict):
        """Print a formatted report"""
        print("\n" + "="*80)
        print("IP ALLOCATION REPORT")
        print("="*80)
        
        # Summary
        print("\nSUMMARY:")
        print(f"  Total IP Allocations: {report['summary']['total_allocations']}")
        print(f"  CIDR Blocks: {report['summary']['cidr_blocks']}")
        print(f"  Individual IPs: {report['summary']['individual_ips']}")
        print(f"  Conflicts Found: {report['summary']['total_conflicts']}")
        
        # CIDR Blocks
        if 'cidr' in report['allocations']:
            print("\nCIDR BLOCKS:")
            for cidr, locations in sorted(report['allocations']['cidr'].items()):
                print(f"\n  {cidr}:")
                for loc in locations:
                    print(f"    - {loc['file']}:{loc['line']} ({loc['context']})")
                    
        # Individual IPs
        if 'ip' in report['allocations']:
            print("\nINDIVIDUAL IPS:")
            for ip, locations in sorted(report['allocations']['ip'].items()):
                print(f"\n  {ip}:")
                for loc in locations:
                    print(f"    - {loc['file']}:{loc['line']} ({loc['context']})")
                    
        # Conflicts
        if report['conflicts']:
            print("\n" + "!"*80)
            print("CONFLICTS DETECTED:")
            for conflict in report['conflicts']:
                print(f"\n  Type: {conflict['type']}")
                print(f"  Network 1: {conflict['network1']}")
                for loc in conflict['locations1']:
                    print(f"    - {loc['file']}:{loc['line']}")
                print(f"  Network 2: {conflict['network2']}")
                for loc in conflict['locations2']:
                    print(f"    - {loc['file']}:{loc['line']}")
                    
        print("\n" + "="*80)
        
    def save_report(self, report: Dict, output_file: str):
        """Save report to a JSON file"""
        with open(output_file, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"\nReport saved to: {output_file}")
        
def main():
    """Main execution function"""
    import argparse
    
    parser = argparse.ArgumentParser(description='Track IP allocations in Terragrunt configurations')
    parser.add_argument('--repo-root', default='.', help='Repository root directory')
    parser.add_argument('--output', help='Output file for JSON report')
    parser.add_argument('--check-only', action='store_true', help='Only check for conflicts')
    
    args = parser.parse_args()
    
    # Initialize tracker
    tracker = IPAllocationTracker(args.repo_root)
    
    # Scan files
    print("Scanning Terragrunt files for IP allocations...")
    tracker.scan_terragrunt_files()
    
    # Check for overlaps
    print("Checking for overlapping CIDR blocks...")
    tracker.check_overlaps()
    
    # Generate report
    report = tracker.generate_report()
    
    # Print report
    if not args.check_only:
        tracker.print_report(report)
        
    # Save report if requested
    if args.output:
        tracker.save_report(report, args.output)
        
    # Exit with error if conflicts found
    if report['conflicts']:
        print("\n⚠️  IP allocation conflicts detected!", file=sys.stderr)
        sys.exit(1)
    else:
        print("\n✅ No IP allocation conflicts found!")
        
if __name__ == "__main__":
    main()