#!/usr/bin/env python3
"""
IP Allocation Checker for terragrunt-gcp-org-automation

This script validates IP allocations, checks for conflicts, and provides
visualization of the IP space usage.

Usage:
    python3 ip-allocation-checker.py [command]

Commands:
    validate    - Check for IP conflicts and validate allocations
    visualize   - Show IP allocation visualization
    available   - Show available IP blocks
    next        - Suggest next available allocation
"""

import ipaddress
import sys
import os
from typing import Dict, List, Tuple, Optional
from collections import defaultdict

try:
    import yaml
except ImportError:
    print("Error: PyYAML module not found.")
    print("Please install it using: pip3 install pyyaml")
    print("Or: pip install pyyaml")
    sys.exit(1)


class IPAllocationChecker:
    def __init__(self, allocation_file: str = "../ip-allocation.yaml"):
        """Initialize the IP allocation checker."""
        self.allocation_file = allocation_file
        self.allocations = self._load_allocations()
        self.networks = []
        self._parse_networks()

    def _load_allocations(self) -> Dict:
        """Load IP allocations from YAML file."""
        script_dir = os.path.dirname(os.path.abspath(__file__))
        file_path = os.path.join(script_dir, self.allocation_file)

        try:
            with open(file_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            print(f"Error: Could not find {file_path}")
            sys.exit(1)
        except yaml.YAMLError as e:
            print(f"Error parsing YAML: {e}")
            sys.exit(1)

    def _parse_networks(self):
        """Parse all networks from the allocation data."""
        # Parse development environments
        dev_envs = self.allocations.get('development', {}).get('environments', {})
        self._parse_environment_networks(dev_envs, 'development')
        
        # Parse perimeter environments
        perimeter_envs = self.allocations.get('perimeter', {}).get('environments', {})
        self._parse_environment_networks(perimeter_envs, 'perimeter')
        
        # Parse production environments
        prod_envs = self.allocations.get('production', {}).get('environments', {})
        self._parse_environment_networks(prod_envs, 'production')

    def _parse_environment_networks(self, envs: Dict, env_type: str):
        """Parse networks for a specific environment type."""
        for env_name, env_data in envs.items():
            if env_data.get('status') in ['active', 'reserved']:
                # Parse primary subnets
                for subnet_name, subnet_data in env_data.get('primary_subnets', {}).items():
                    if 'cidr' in subnet_data:
                        self.networks.append({
                            'name': f"{env_type}/{env_name}/{subnet_name}",
                            'network': ipaddress.IPv4Network(subnet_data['cidr']),
                            'type': 'primary',
                            'env': env_name,
                            'env_type': env_type,
                            'description': subnet_data.get('description', '')
                        })

                # Parse secondary ranges (for GKE)
                for range_name, range_data in env_data.get('secondary_ranges', {}).items():
                    if 'cidr' in range_data:
                        self.networks.append({
                            'name': f"{env_type}/{env_name}/{range_name}",
                            'network': ipaddress.IPv4Network(range_data['cidr']),
                            'type': 'secondary',
                            'env': env_name,
                            'env_type': env_type,
                            'description': range_data.get('description', '')
                        })

    def validate(self) -> bool:
        """Validate IP allocations for conflicts."""
        print("🔍 Validating IP allocations...\n")

        conflicts = []
        valid = True

        # Check for overlapping networks
        for i, net1 in enumerate(self.networks):
            for net2 in self.networks[i+1:]:
                if net1['network'].overlaps(net2['network']):
                    conflicts.append((net1, net2))
                    valid = False

        if conflicts:
            print("❌ Found IP conflicts:")
            for net1, net2 in conflicts:
                print(f"\n  Conflict between:")
                print(f"    - {net1['name']}: {net1['network']}")
                print(f"    - {net2['name']}: {net2['network']}")
        else:
            print("✅ No IP conflicts found!")

        # Validate CIDR boundaries
        print("\n🔍 Checking CIDR boundaries...")
        boundary_issues = []
        for net in self.networks:
            network = net['network']
            prefix = network.prefixlen
            
            # Check alignment based on prefix length
            if prefix == 21:
                # /21 must be divisible by 8
                third_octet = int(str(network.network_address).split('.')[2])
                if third_octet % 8 != 0:
                    boundary_issues.append(f"{net['name']}: /21 not aligned (third octet {third_octet} not divisible by 8)")
            elif prefix == 18:
                # /18 must be divisible by 64
                third_octet = int(str(network.network_address).split('.')[2])
                if third_octet % 64 != 0:
                    boundary_issues.append(f"{net['name']}: /18 not aligned (third octet {third_octet} not divisible by 64)")
            elif prefix == 19:
                # /19 must be divisible by 32
                third_octet = int(str(network.network_address).split('.')[2])
                if third_octet % 32 != 0:
                    boundary_issues.append(f"{net['name']}: /19 not aligned (third octet {third_octet} not divisible by 32)")

        if boundary_issues:
            print("⚠️  CIDR boundary issues found:")
            for issue in boundary_issues:
                print(f"    - {issue}")
            valid = False
        else:
            print("✅ All CIDR boundaries are valid!")

        return valid

    def visualize(self):
        """Visualize IP allocations."""
        print("📊 IP Allocation Visualization\n")

        # Group by environment type
        by_type = defaultdict(lambda: defaultdict(list))
        for net in sorted(self.networks, key=lambda x: x['network'].network_address):
            by_type[net['env_type']][net['env']].append(net)

        for env_type in ['development', 'perimeter', 'production']:
            if env_type in by_type:
                print(f"\n🌐 {env_type.upper()} Environments")
                print("  " + "=" * 70)
                
                type_data = self.allocations.get(env_type, {})
                if 'block' in type_data:
                    print(f"  Block: {type_data['block']} ({type_data.get('total_ips', 'N/A'):,} IPs)")
                
                for env, nets in by_type[env_type].items():
                    print(f"\n  📁 Environment: {env}")
                    print("  " + "─" * 60)

                    # Show environment block
                    env_data = type_data.get('environments', {}).get(env, {})
                    if 'block' in env_data:
                        print(f"    Block: {env_data['block']} ({env_data.get('total_ips', 'N/A'):,} IPs)")
                        print(f"    Status: {env_data.get('status', 'unknown')}")

                    # Show subnets
                    primary_nets = [n for n in nets if n['type'] == 'primary']
                    if primary_nets:
                        print("\n    Primary Subnets:")
                        for net in primary_nets:
                            name_part = net['name'].split('/')[-1]
                            print(f"      {name_part:<20} {str(net['network']):<18} "
                                  f"({net['network'].num_addresses:>6,} IPs)")
                            if net['description']:
                                print(f"        └─ {net['description']}")

                    secondary_nets = [n for n in nets if n['type'] == 'secondary']
                    if secondary_nets:
                        print("\n    Secondary Ranges (GKE):")
                        for net in secondary_nets:
                            name_part = net['name'].split('/')[-1]
                            print(f"      {name_part:<20} {str(net['network']):<18} "
                                  f"({net['network'].num_addresses:>6,} IPs)")
                            if net['description']:
                                print(f"        └─ {net['description']}")

    def show_available(self):
        """Show available IP blocks."""
        print("🆓 Available IP Allocations\n")

        # Show development block
        dev_block = ipaddress.IPv4Network(self.allocations['development']['block'])
        print(f"Development Block: {dev_block} ({dev_block.num_addresses:,} total IPs)")
        
        # Show reserved environments
        print("\nReserved Development Environments (ready for use):")
        dev_envs = self.allocations['development']['environments']
        for env_name, env_data in dev_envs.items():
            if env_data.get('status') == 'reserved':
                print(f"  - {env_name}: {env_data['block']} ({env_data.get('total_ips', 65536):,} IPs)")

        # Show perimeter block
        perimeter_block = ipaddress.IPv4Network(self.allocations['perimeter']['block'])
        print(f"\nPerimeter Block: {perimeter_block} ({perimeter_block.num_addresses:,} total IPs)")
        
        # Show production block
        prod_block = ipaddress.IPv4Network(self.allocations['production']['block'])
        print(f"\nProduction Block: {prod_block} ({prod_block.num_addresses:,} total IPs)")

        # Calculate next available environment
        used_blocks = []
        for env_data in dev_envs.values():
            if 'block' in env_data:
                used_blocks.append(ipaddress.IPv4Network(env_data['block']))

        print(f"\nNext available environment blocks:")
        next_base = 10
        next_third = 136  # After dev-04 (10.135.0.0/16)
        for i in range(5):
            candidate = ipaddress.IPv4Network(f"{next_base}.{next_third}.0.0/16")
            if not any(candidate.overlaps(used) for used in used_blocks):
                print(f"  - dev-{len(dev_envs)+i+1:02d}: {candidate}")
            next_third += 1

    def suggest_next_cluster(self, env: str = 'dp-dev-01'):
        """Suggest next available cluster allocation."""
        print(f"🔮 Next available allocations for {env}\n")

        # Search in all environment types
        for env_type in ['development', 'perimeter', 'production']:
            env_data = self.allocations.get(env_type, {}).get('environments', {}).get(env)
            if env_data:
                break
        else:
            print(f"Environment {env} not found!")
            return

        # Find next cluster ranges
        secondary_ranges = env_data.get('secondary_ranges', {})
        
        # Count allocated clusters
        allocated_clusters = set()
        for range_name in secondary_ranges.keys():
            if '-' in range_name:
                cluster_name = range_name.split('-')[0] + '-' + range_name.split('-')[1]
                allocated_clusters.add(cluster_name)
        
        next_cluster_num = len(allocated_clusters) + 1
        next_cluster_name = f"cluster-{next_cluster_num:02d}"
        
        print(f"Next cluster: {next_cluster_name}")
        
        # Check if ranges are pre-allocated
        pod_range_name = f"{next_cluster_name}-pods"
        service_range_name = f"{next_cluster_name}-services"
        
        if pod_range_name in secondary_ranges:
            pod_data = secondary_ranges[pod_range_name]
            print(f"  Pod range:     {pod_data['cidr']} ({pod_data['size']:,} IPs)")
        else:
            print(f"  Pod range:     Not pre-allocated")
            
        if service_range_name in secondary_ranges:
            service_data = secondary_ranges[service_range_name]
            print(f"  Service range: {service_data['cidr']} ({service_data['size']:,} IPs)")
        else:
            print(f"  Service range: Not pre-allocated")
            
        if pod_range_name not in secondary_ranges:
            print("\nNo more pre-allocated cluster ranges available.")
            print("Additional ranges need to be defined in ip-allocation.yaml")


def main():
    """Main entry point."""
    checker = IPAllocationChecker()

    if len(sys.argv) < 2:
        command = "validate"
    else:
        command = sys.argv[1]

    if command == "validate":
        checker.validate()
    elif command == "visualize":
        checker.visualize()
    elif command == "available":
        checker.show_available()
    elif command == "next":
        env = sys.argv[2] if len(sys.argv) > 2 else 'dp-dev-01'
        checker.suggest_next_cluster(env)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()