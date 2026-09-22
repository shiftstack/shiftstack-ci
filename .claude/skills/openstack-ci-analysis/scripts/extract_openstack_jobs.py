#!/usr/bin/env python3
"""
Extract all OpenStack CI jobs from ci-operator/config files.

This script parses CI configuration files and extracts job information
for tests using OpenStack cluster profiles.

Target cluster profiles:
- openstack-vexxhost
- openstack-vh-mecha-central
- openstack-vh-mecha-az0
- openstack-vh-bm-rhos
- openstack-hwoffload
- openstack-nfv
"""

import argparse
import csv
import json
import os
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


# Target OpenStack cluster profiles
OPENSTACK_PROFILES = [
    "openstack-vexxhost",
    "openstack-vh-mecha-central",
    "openstack-vh-mecha-az0",
    "openstack-vh-bm-rhos",
    "openstack-hwoffload",
    "openstack-nfv",
]


def get_cluster_profile(test):
    """Extract cluster_profile from a test definition."""
    if "steps" in test:
        steps = test["steps"]
        if isinstance(steps, dict):
            return steps.get("cluster_profile")
    return None


def get_workflow(test):
    """Extract workflow from a test definition."""
    if "steps" in test:
        steps = test["steps"]
        if isinstance(steps, dict):
            return steps.get("workflow")
    return None


def get_job_type(test):
    """Determine job type based on scheduling fields.

    Jobs are classified as:
    - periodic: if they have cron/interval, OR if they have minimum_interval
                but no presubmit triggers (always_run, run_if_changed, optional)
    - postsubmit: if explicitly marked as postsubmit
    - presubmit: otherwise

    Note: Jobs with minimum_interval but no presubmit triggers are periodic jobs
    that run on a schedule. They're generated into *-periodics.yaml files.
    """
    # Explicit periodic scheduling
    if test.get("interval") or test.get("cron"):
        return "periodic"

    if test.get("postsubmit"):
        return "postsubmit"

    # Implicit periodic: minimum_interval without presubmit triggers
    # These jobs run periodically, not on PRs
    if test.get("minimum_interval"):
        has_presubmit_trigger = (
            test.get("always_run") or
            test.get("run_if_changed") or
            test.get("optional") is True or
            test.get("skip_if_only_changed")
        )
        if not has_presubmit_trigger:
            return "periodic"

    return "presubmit"


def get_schedule(test):
    """Extract schedule (interval or cron) from a test.

    For implicit periodic jobs (those with minimum_interval but no presubmit
    triggers), the minimum_interval acts as the schedule.
    """
    if test.get("interval"):
        return f"interval: {test['interval']}"
    if test.get("cron"):
        return f"cron: {test['cron']}"
    # For implicit periodic jobs, minimum_interval is the effective schedule
    if test.get("minimum_interval"):
        has_presubmit_trigger = (
            test.get("always_run") or
            test.get("run_if_changed") or
            test.get("optional") is True or
            test.get("skip_if_only_changed")
        )
        if not has_presubmit_trigger:
            return f"minimum_interval: {test['minimum_interval']}"
    return ""


def parse_config_file(file_path):
    """Parse a single CI config file and extract OpenStack jobs."""
    jobs = []

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
    except Exception as e:
        print(f"Warning: Failed to parse {file_path}: {e}", file=sys.stderr)
        return jobs

    if not config or "tests" not in config:
        return jobs

    # Extract metadata
    metadata = config.get("zz_generated_metadata", {})
    org = metadata.get("org", "")
    repo = metadata.get("repo", "")
    branch = metadata.get("branch", "")
    variant = metadata.get("variant", "")

    # Parse each test
    for test in config.get("tests", []):
        if not isinstance(test, dict):
            continue

        cluster_profile = get_cluster_profile(test)

        # Check if this is an OpenStack job
        if cluster_profile and any(profile in cluster_profile for profile in OPENSTACK_PROFILES):
            job_name = test.get("as", "")

            job_info = {
                "job_name": job_name,
                "cluster_profile": cluster_profile,
                "job_type": get_job_type(test),
                "schedule": get_schedule(test),
                "workflow": get_workflow(test) or "",
                "optional": test.get("optional", False),
                "always_run": test.get("always_run", False),
                "minimum_interval": test.get("minimum_interval", ""),
                "skip_if_only_changed": test.get("skip_if_only_changed", ""),
                "run_if_changed": test.get("run_if_changed", ""),
                "org": org,
                "repo": repo,
                "branch": branch,
                "variant": variant,
                "config_file": str(file_path),
            }

            jobs.append(job_info)

    return jobs


def find_config_files(config_dir):
    """Find all CI config YAML files."""
    config_path = Path(config_dir)

    yaml_files = []
    for pattern in ["**/*.yaml", "**/*.yml"]:
        yaml_files.extend(config_path.glob(pattern))

    return sorted(set(yaml_files))


def extract_jobs(config_dir):
    """Extract all OpenStack jobs from config directory."""
    all_jobs = []

    config_files = find_config_files(config_dir)
    print(f"Found {len(config_files)} config files to scan", file=sys.stderr)

    for file_path in config_files:
        jobs = parse_config_file(file_path)
        all_jobs.extend(jobs)

    print(f"Extracted {len(all_jobs)} OpenStack jobs", file=sys.stderr)
    return all_jobs


def output_csv(jobs, output_file):
    """Output jobs to CSV format."""
    if not jobs:
        print("No jobs to output", file=sys.stderr)
        return

    fieldnames = [
        "job_name", "cluster_profile", "job_type", "schedule", "workflow",
        "optional", "always_run", "minimum_interval", "skip_if_only_changed",
        "run_if_changed", "org", "repo", "branch", "variant", "config_file"
    ]

    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(jobs)

    print(f"Wrote {len(jobs)} jobs to {output_file}", file=sys.stderr)


def output_json(jobs, output_file):
    """Output jobs to JSON format."""
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(jobs, f, indent=2)

    print(f"Wrote {len(jobs)} jobs to {output_file}", file=sys.stderr)


def print_summary(jobs):
    """Print summary statistics."""
    print("\n=== OpenStack CI Job Summary ===\n")

    # By cluster profile
    profile_counts = {}
    for job in jobs:
        profile = job["cluster_profile"]
        profile_counts[profile] = profile_counts.get(profile, 0) + 1

    print("Jobs by Cluster Profile:")
    for profile in sorted(profile_counts.keys()):
        print(f"  {profile}: {profile_counts[profile]}")

    # By job type
    type_counts = {}
    for job in jobs:
        job_type = job["job_type"]
        type_counts[job_type] = type_counts.get(job_type, 0) + 1

    print("\nJobs by Type:")
    for job_type in sorted(type_counts.keys()):
        print(f"  {job_type}: {type_counts[job_type]}")

    # By org
    org_counts = {}
    for job in jobs:
        org = job["org"] or "unknown"
        org_counts[org] = org_counts.get(org, 0) + 1

    print("\nJobs by Organization:")
    for org in sorted(org_counts.keys(), key=lambda x: org_counts[x], reverse=True)[:10]:
        print(f"  {org}: {org_counts[org]}")

    # Unique workflows
    workflows = set(job["workflow"] for job in jobs if job["workflow"])
    print(f"\nUnique Workflows: {len(workflows)}")

    # Unique repos
    repos = set(f"{job['org']}/{job['repo']}" for job in jobs if job['org'] and job['repo'])
    print(f"Unique Repositories: {len(repos)}")

    # Release branches
    branches = set(job["branch"] for job in jobs if job["branch"])
    release_branches = sorted([b for b in branches if "release-" in b or b in ["main", "master"]])
    print(f"\nRelease Branches:")
    for branch in release_branches[-10:]:
        count = len([j for j in jobs if j["branch"] == branch])
        print(f"  {branch}: {count}")

    print()


def main():
    parser = argparse.ArgumentParser(
        description="Extract OpenStack CI jobs from ci-operator config files"
    )
    parser.add_argument(
        "--config-dir",
        default="ci-operator/config",
        help="Path to ci-operator/config directory (default: ci-operator/config)"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for output files (default: script directory)"
    )
    parser.add_argument(
        "--output-csv",
        default="openstack_jobs_inventory.csv",
        help="Output CSV filename (default: openstack_jobs_inventory.csv)"
    )
    parser.add_argument(
        "--output-json",
        default="openstack_jobs_inventory.json",
        help="Output JSON filename (default: openstack_jobs_inventory.json)"
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print summary statistics"
    )

    args = parser.parse_args()

    # Resolve output directory
    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)

    print("=" * 60)
    print("OpenStack CI Job Extractor")
    print("=" * 60)
    print(f"Config directory: {args.config_dir}")
    print(f"Output directory: {output_dir}")
    print()

    # Ensure config directory exists
    if not os.path.isdir(args.config_dir):
        print(f"Error: Config directory not found: {args.config_dir}", file=sys.stderr)
        sys.exit(1)

    # Extract jobs
    jobs = extract_jobs(args.config_dir)

    # Output CSV
    csv_path = os.path.join(output_dir, args.output_csv)
    output_csv(jobs, csv_path)

    # Output JSON
    json_path = os.path.join(output_dir, args.output_json)
    output_json(jobs, json_path)

    # Print summary if requested
    if args.summary:
        print_summary(jobs)


if __name__ == "__main__":
    main()
