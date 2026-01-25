#!/usr/bin/env python3
"""
Analyze OpenStack CI test coverage across releases.

This script identifies:
1. Coverage matrix (which tests run on which releases)
2. Coverage gaps (tests missing from certain releases)
3. Release-to-release differences
4. Workflow usage across releases
"""

import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path


# Current and recent releases to focus on
ACTIVE_RELEASES = [
    "release-4.17",
    "release-4.18",
    "release-4.19",
    "release-4.20",
    "release-4.21",
    "release-4.22",
    "release-4.23",
]

MAIN_BRANCHES = ["main", "master"]


def load_inventory(csv_path):
    """Load job inventory from CSV."""
    jobs = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            row['optional'] = row['optional'].lower() == 'true'
            row['always_run'] = row['always_run'].lower() == 'true'
            jobs.append(row)
    return jobs


def normalize_branch(branch):
    """Normalize branch name for comparison."""
    if branch in MAIN_BRANCHES:
        return "main/master"
    return branch


def get_release_version(branch):
    """Extract version number from release branch."""
    if branch.startswith("release-"):
        return branch.replace("release-", "")
    return None


def build_test_matrix(jobs):
    """
    Build a matrix of tests by (workflow, cluster_profile) across releases.
    """
    # Group by (org, repo) to see coverage per repo
    repo_coverage = defaultdict(lambda: defaultdict(set))

    # Group by (workflow, cluster_profile) to see overall test coverage
    test_coverage = defaultdict(set)

    for job in jobs:
        org = job['org']
        repo = job['repo']
        branch = job['branch']
        workflow = job['workflow']
        cluster = job['cluster_profile']
        job_name = job['job_name']

        # Normalize branch
        normalized = normalize_branch(branch)

        # Track per-repo coverage
        if workflow:
            key = (org, repo, job_name, workflow, cluster)
            repo_coverage[key][normalized].add(job['config_file'])

        # Track workflow coverage
        if workflow:
            test_key = (workflow, cluster, job_name)
            test_coverage[test_key].add(normalized)

    return repo_coverage, test_coverage


def analyze_release_coverage(jobs):
    """
    Analyze which releases have what coverage.
    """
    # Count jobs per release
    release_counts = defaultdict(int)
    for job in jobs:
        branch = normalize_branch(job['branch'])
        release_counts[branch] += 1

    # Count unique test types per release
    release_tests = defaultdict(set)
    for job in jobs:
        branch = normalize_branch(job['branch'])
        key = (job['workflow'], job['cluster_profile'], job['job_name'])
        release_tests[branch].add(key)

    return release_counts, release_tests


def find_coverage_gaps(jobs):
    """
    Find tests that exist in some releases but not others.
    """
    # Group jobs by (org, repo, job_name)
    job_releases = defaultdict(set)
    for job in jobs:
        key = (job['org'], job['repo'], job['job_name'])
        job_releases[key].add(job['branch'])

    # Get all releases present per repo
    repo_releases = defaultdict(set)
    for job in jobs:
        key = (job['org'], job['repo'])
        repo_releases[key].add(job['branch'])

    # Find gaps
    gaps = []
    for (org, repo, job_name), present_releases in job_releases.items():
        all_releases = repo_releases[(org, repo)]

        # Focus on active releases
        active_present = set(r for r in present_releases if r in ACTIVE_RELEASES)
        active_all = set(r for r in all_releases if r in ACTIVE_RELEASES)

        # If job exists in some active releases but not all, it's a gap
        missing = active_all - active_present
        if missing and active_present:  # Has some active releases but missing others
            gaps.append({
                'org': org,
                'repo': repo,
                'job_name': job_name,
                'present': sorted(active_present),
                'missing': sorted(missing),
            })

    return gaps


def analyze_workflow_coverage(jobs):
    """
    Analyze which workflows are used in which releases.
    """
    workflow_releases = defaultdict(lambda: defaultdict(int))

    for job in jobs:
        workflow = job['workflow']
        if not workflow:
            continue
        branch = job['branch']
        if branch in ACTIVE_RELEASES or branch in MAIN_BRANCHES:
            normalized = normalize_branch(branch)
            workflow_releases[workflow][normalized] += 1

    return workflow_releases


def analyze_cluster_profile_usage(jobs):
    """
    Analyze cluster profile usage by release.
    """
    profile_releases = defaultdict(lambda: defaultdict(int))

    for job in jobs:
        profile = job['cluster_profile']
        branch = job['branch']
        if branch in ACTIVE_RELEASES or branch in MAIN_BRANCHES:
            normalized = normalize_branch(branch)
            profile_releases[profile][normalized] += 1

    return profile_releases


def generate_report(jobs, output_file):
    """Generate comprehensive coverage report."""
    report = []
    report.append("# OpenStack CI Test Coverage Analysis Report\n")
    report.append(f"Total jobs analyzed: {len(jobs)}\n")

    # Release Coverage Summary
    report.append("\n## 1. Jobs by Release\n\n")
    release_counts, release_tests = analyze_release_coverage(jobs)

    # Sort releases naturally
    def sort_key(r):
        if r == "main/master":
            return (1, "zzz")
        if r.startswith("release-"):
            ver = r.replace("release-", "")
            parts = ver.split(".")
            return (0, tuple(int(p) for p in parts if p.isdigit()))
        return (2, r)

    sorted_releases = sorted(release_counts.keys(), key=sort_key)

    report.append("| Release | Total Jobs | Unique Tests |\n")
    report.append("|---------|------------|---------------|\n")
    for release in sorted_releases[-15:]:  # Last 15 releases
        count = release_counts[release]
        unique = len(release_tests[release])
        report.append(f"| {release} | {count} | {unique} |\n")

    # Cluster Profile Usage
    report.append("\n## 2. Cluster Profile Usage by Release\n\n")
    profile_usage = analyze_cluster_profile_usage(jobs)

    # Header
    active_releases_sorted = sorted(
        [normalize_branch(r) for r in ACTIVE_RELEASES + MAIN_BRANCHES],
        key=sort_key
    )[-6:]  # Last 6

    report.append("| Cluster Profile | " +
                  " | ".join(active_releases_sorted) + " |\n")
    report.append("|" + "-" * 17 + "|" +
                  "|".join(["-" * 8 for _ in active_releases_sorted]) + "|\n")

    for profile in sorted(profile_usage.keys()):
        counts = [str(profile_usage[profile].get(r, 0))
                  for r in active_releases_sorted]
        report.append(f"| {profile} | " + " | ".join(counts) + " |\n")

    # Workflow Usage
    report.append("\n## 3. Workflow Usage by Release\n\n")
    workflow_usage = analyze_workflow_coverage(jobs)

    report.append("| Workflow | " +
                  " | ".join(active_releases_sorted) + " |\n")
    report.append("|" + "-" * 40 + "|" +
                  "|".join(["-" * 8 for _ in active_releases_sorted]) + "|\n")

    for workflow in sorted(workflow_usage.keys()):
        counts = [str(workflow_usage[workflow].get(r, 0))
                  for r in active_releases_sorted]
        report.append(f"| {workflow} | " + " | ".join(counts) + " |\n")

    # Coverage Gaps
    report.append("\n## 4. Coverage Gaps\n")
    report.append("Tests present in some active releases but missing from others.\n\n")

    gaps = find_coverage_gaps(jobs)

    if gaps:
        # Group by repo
        repo_gaps = defaultdict(list)
        for gap in gaps:
            repo_gaps[(gap['org'], gap['repo'])].append(gap)

        report.append(f"Found {len(gaps)} coverage gaps across "
                      f"{len(repo_gaps)} repositories.\n\n")

        report.append("### By Repository\n\n")
        for (org, repo), repo_gap_list in sorted(repo_gaps.items()):
            report.append(f"#### {org}/{repo}\n\n")
            report.append("| Job | Present | Missing |\n")
            report.append("|-----|---------|----------|\n")
            for gap in repo_gap_list[:10]:
                present = ', '.join(gap['present'][:3])
                if len(gap['present']) > 3:
                    present += f" (+{len(gap['present'])-3})"
                missing = ', '.join(gap['missing'][:3])
                if len(gap['missing']) > 3:
                    missing += f" (+{len(gap['missing'])-3})"
                report.append(f"| {gap['job_name']} | {present} | {missing} |\n")
            if len(repo_gap_list) > 10:
                report.append(f"\n... and {len(repo_gap_list)-10} more gaps\n")
            report.append("\n")
    else:
        report.append("No coverage gaps found in active releases.\n")

    # Test Type Analysis
    report.append("\n## 5. Test Type Coverage\n")
    report.append("Summary of test types and their coverage.\n\n")

    # Categorize by test name patterns
    test_categories = {
        'e2e-basic': [],
        'e2e-conformance': [],
        'e2e-csi': [],
        'e2e-nfv': [],
        'e2e-upgrade': [],
        'e2e-other': [],
    }

    for job in jobs:
        name = job['job_name'].lower()
        if 'csi' in name or 'manila' in name or 'cinder' in name:
            test_categories['e2e-csi'].append(job)
        elif 'nfv' in name or 'sriov' in name or 'hwoffload' in name:
            test_categories['e2e-nfv'].append(job)
        elif 'upgrade' in name:
            test_categories['e2e-upgrade'].append(job)
        elif 'parallel' in name or 'serial' in name or 'conformance' in name:
            test_categories['e2e-conformance'].append(job)
        elif name.endswith('e2e-openstack') or name == 'e2e-openstack-ovn':
            test_categories['e2e-basic'].append(job)
        else:
            test_categories['e2e-other'].append(job)

    report.append("| Category | Total Jobs | Unique Tests |\n")
    report.append("|----------|------------|---------------|\n")
    for category, cat_jobs in sorted(test_categories.items()):
        unique = len(set((j['job_name'], j['workflow']) for j in cat_jobs))
        report.append(f"| {category} | {len(cat_jobs)} | {unique} |\n")

    # Recommendations
    report.append("\n## 6. Coverage Recommendations\n\n")

    report.append("### Missing Coverage Areas\n\n")

    # Check for releases with low coverage
    active_counts = {r: release_counts.get(r, 0)
                     for r in ACTIVE_RELEASES}
    avg_count = sum(active_counts.values()) / len(active_counts) if active_counts else 0

    low_coverage = [r for r, c in active_counts.items() if c < avg_count * 0.7]
    if low_coverage:
        report.append(f"1. **Low coverage releases**: {', '.join(sorted(low_coverage))} "
                      f"have fewer jobs than average.\n\n")

    # Check for profile gaps
    for profile in sorted(profile_usage.keys()):
        releases_with_profile = [r for r, c in profile_usage[profile].items() if c > 0]
        if len(releases_with_profile) < len(active_releases_sorted) - 1:
            missing = set(active_releases_sorted) - set(releases_with_profile)
            if missing:
                report.append(f"2. **{profile}**: Missing from {', '.join(sorted(missing))}\n\n")

    report.append("### Consolidation Opportunities\n\n")
    report.append("- Jobs that appear in all releases with same config could use shared workflows\n")
    report.append("- Consider periodic-only coverage for older releases (4.17, 4.18)\n")
    report.append("- Evaluate if all cluster profiles need coverage in all releases\n")

    # Write report
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(''.join(report))

    print(f"Report written to {output_file}", file=sys.stderr)

    # Also write machine-readable data
    json_output = output_file.replace('.md', '_data.json')
    with open(json_output, 'w', encoding='utf-8') as f:
        json.dump({
            'release_counts': dict(release_counts),
            'workflow_usage': {k: dict(v) for k, v in workflow_usage.items()},
            'profile_usage': {k: dict(v) for k, v in profile_usage.items()},
            'coverage_gaps': gaps[:100],
            'test_categories': {k: len(v) for k, v in test_categories.items()},
        }, f, indent=2)

    print(f"Data written to {json_output}", file=sys.stderr)


def main():
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(
        description="Analyze OpenStack CI test coverage"
    )
    parser.add_argument(
        "--output-dir",
        default=script_dir,
        help="Directory for input/output files (default: script directory)"
    )
    parser.add_argument(
        "--inventory",
        default="openstack_jobs_inventory.csv",
        help="Inventory CSV filename (default: openstack_jobs_inventory.csv)"
    )

    args = parser.parse_args()

    output_dir = os.path.abspath(args.output_dir)

    print("=" * 60)
    print("OpenStack CI Coverage Analysis")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print()

    inventory_path = os.path.join(output_dir, args.inventory)
    output_path = os.path.join(output_dir, "coverage_gaps_report.md")

    jobs = load_inventory(inventory_path)
    generate_report(jobs, output_path)


if __name__ == "__main__":
    main()
