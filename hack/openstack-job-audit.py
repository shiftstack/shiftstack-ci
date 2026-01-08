#!/usr/bin/env python3
"""
Audits CI configuration files to find OpenStack e2e test jobs and reports
their run_if_changed and skip_if_only_changed settings.

Usage: ./openstack-job-audit.py <project_path> [output_file]
  project_path: Path to the project root (ci-operator/config will be appended)
  output_file: Output file path (default: ./openstack-ci-report.yaml)

Example: ./openstack-job-audit.py /path/to/openshift/release ./report.yaml
"""

import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

import yaml
from ruamel.yaml import YAML


def find_vexxhost_files(config_base_path: Path) -> dict[str, list[Path]]:
    """
    Find all config files containing vexxhost cluster_profile.

    Returns a dict mapping project (org/repo) to list of matching files.
    """
    pattern = re.compile(r'cluster_profile:.*vexxhost.*')
    projects = defaultdict(list)

    for file_path in config_base_path.rglob('*.yaml'):
        try:
            content = file_path.read_text()
            if pattern.search(content):
                # Extract project as org/repo from path
                # Path structure: config_base_path/org/repo/file.yaml
                rel_path = file_path.relative_to(config_base_path)
                parts = rel_path.parts
                if len(parts) >= 2:
                    project = f"{parts[0]}/{parts[1]}"
                    projects[project].append(file_path)
        except (OSError, UnicodeDecodeError):
            continue

    return projects


def extract_vexxhost_tests(file_path: Path) -> list[dict]:
    """
    Extract test jobs with vexxhost cluster_profile from a config file.

    Returns list of dicts with test name and settings.
    """
    try:
        with open(file_path) as f:
            config = yaml.safe_load(f)
    except (OSError, yaml.YAMLError):
        return []

    if not config or 'tests' not in config:
        return []

    vexxhost_pattern = re.compile(r'.*vexxhost.*')
    results = []

    for test in config.get('tests', []):
        steps = test.get('steps', {})
        cluster_profile = steps.get('cluster_profile', '')

        if vexxhost_pattern.match(str(cluster_profile)):
            test_data = {
                'name': test.get('as', 'unknown'),
                'run_if_changed': test.get('run_if_changed', 'not set'),
                'skip_if_only_changed': test.get('skip_if_only_changed',
                                                 'not set'),
            }
            if 'interval' in test:
                test_data['interval'] = test.get('interval')
            if 'minimum_interval' in test:
                test_data['minimum_interval'] = test.get('minimum_interval')
            results.append(test_data)

    return results


def generate_report(config_base_path: Path) -> dict:
    """
    Generate the audit report for all projects.

    Returns a dict structured for YAML output.
    """
    projects = find_vexxhost_files(config_base_path)
    report = {}

    for project in sorted(projects.keys()):
        files = sorted(projects[project])
        project_data = []

        for file_path in files:
            tests = extract_vexxhost_tests(file_path)
            if tests:
                file_entry = {
                    'file': str(file_path),
                    'tests': tests,
                }
                project_data.append(file_entry)

        if project_data:
            report[project] = project_data

    return report


def main():
    parser = argparse.ArgumentParser(
        description="Audit CI config files for OpenStack e2e test jobs"
    )
    parser.add_argument(
        "project_path",
        type=Path,
        help="Path to the project root (ci-operator/config will be appended)",
    )
    parser.add_argument(
        "output_file",
        nargs="?",
        type=Path,
        default=Path("./openstack-ci-report.yaml"),
        help="Output file path (default: ./openstack-ci-report.yaml)",
    )
    args = parser.parse_args()

    config_base_path = args.project_path / "ci-operator" / "config"

    if not config_base_path.is_dir():
        print(
            f"Error: {config_base_path} is not a directory",
            file=sys.stderr
        )
        sys.exit(1)

    report = generate_report(config_base_path)

    ruamel = YAML()
    ruamel.default_flow_style = False
    ruamel.width = 4096
    ruamel.indent(mapping=2, sequence=4, offset=2)

    with open(args.output_file, 'w') as f:
        ruamel.dump(report, f)

    print(f"Report written to {args.output_file}")


if __name__ == "__main__":
    main()
