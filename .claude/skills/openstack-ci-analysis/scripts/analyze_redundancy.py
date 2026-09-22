#!/usr/bin/env python3
"""
Analyze OpenStack CI jobs for redundancy and consolidation opportunities.

This script identifies:
1. Duplicate jobs between openshift and openshift-priv organizations
2. Similar tests running on the same code paths
3. Jobs with overlapping functionality
4. Presubmit jobs that could be consolidated
"""

import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path


def load_inventory(csv_path):
    """Load job inventory from CSV."""
    jobs = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            # Convert boolean strings to actual booleans
            row['optional'] = row['optional'].lower() == 'true'
            row['always_run'] = row['always_run'].lower() == 'true'
            jobs.append(row)
    return jobs


def analyze_same_workflow_same_branch(jobs):
    """
    Find cases where multiple jobs in the SAME repo/branch use identical
    workflow + cluster_profile combinations.

    These might be testing overlapping functionality and could potentially
    be consolidated, though they may have different env vars or test suites.

    NOTE: Jobs existing across different branches is EXPECTED, not redundant.
    NOTE: Jobs in openshift/ vs openshift-priv/ are separate GitHub gates, not redundant.
    """
    duplicates = []

    # Group jobs by (org, repo, branch, workflow, cluster_profile)
    job_groups = defaultdict(list)
    for job in jobs:
        if not job['workflow']:
            continue
        key = (
            job['org'],
            job['repo'],
            job['branch'],
            job['workflow'],
            job['cluster_profile']
        )
        job_groups[key].append(job)

    for key, group in job_groups.items():
        if len(group) > 1:
            duplicates.append({
                'org': key[0],
                'repo': key[1],
                'branch': key[2],
                'workflow': key[3],
                'cluster_profile': key[4],
                'job_count': len(group),
                'jobs': [j['job_name'] for j in group],
                'files': list(set(j['config_file'] for j in group))
            })

    return duplicates


def analyze_presubmit_triggers(jobs):
    """
    Analyze presubmit job trigger patterns.
    Identify jobs that are always_run=true without throttling.
    """
    presubmit_jobs = [j for j in jobs if j['job_type'] == 'presubmit']

    # Group by trigger pattern
    always_run_no_throttle = []
    always_run_with_throttle = []
    optional_jobs = []
    conditional_jobs = []

    for job in presubmit_jobs:
        if job['always_run']:
            if job['minimum_interval']:
                always_run_with_throttle.append(job)
            else:
                always_run_no_throttle.append(job)
        elif job['optional']:
            optional_jobs.append(job)
        elif job['run_if_changed'] or job['skip_if_only_changed']:
            conditional_jobs.append(job)
        else:
            # Default presubmit (runs on PR but not always)
            optional_jobs.append(job)

    return {
        'always_run_no_throttle': always_run_no_throttle,
        'always_run_with_throttle': always_run_with_throttle,
        'optional': optional_jobs,
        'conditional': conditional_jobs,
    }


def analyze_branch_consistency(jobs):
    """
    Find jobs that exist on some branches but not others.
    Helps identify inconsistent coverage across releases.
    """
    # Group by (org, repo, job_name)
    job_groups = defaultdict(set)
    for job in jobs:
        key = (job['org'], job['repo'], job['job_name'])
        job_groups[key].add(job['branch'])

    # Find jobs that have inconsistent branch coverage
    inconsistencies = []
    repo_branches = defaultdict(set)

    for job in jobs:
        repo_branches[(job['org'], job['repo'])].add(job['branch'])

    for (org, repo, job_name), branches in job_groups.items():
        all_branches = repo_branches[(org, repo)]
        missing = all_branches - branches
        if missing and len(branches) > 1:
            inconsistencies.append({
                'org': org,
                'repo': repo,
                'job_name': job_name,
                'present_branches': sorted(branches),
                'missing_branches': sorted(missing),
            })

    return inconsistencies


def generate_report(jobs, output_file):
    """Generate comprehensive redundancy report."""
    report = []
    report.append("# OpenStack CI Job Redundancy Analysis Report\n")
    report.append(f"Total jobs analyzed: {len(jobs)}\n")

    report.append("\n## Understanding This Report\n\n")
    report.append("**What is NOT redundant:**\n")
    report.append("- Jobs existing across different branches (release-4.20, release-4.21, etc.)\n")
    report.append("- Jobs in both openshift/ and openshift-priv/ (separate GitHub gates)\n\n")
    report.append("**What MAY be redundant:**\n")
    report.append("- Multiple jobs in the SAME repo/branch using identical workflow+cluster\n")
    report.append("- Jobs with overlapping test coverage\n\n")

    # Same Workflow/Cluster in Same Repo/Branch
    report.append("\n## 1. Multiple Jobs with Same Workflow+Cluster\n")
    report.append("Cases where multiple jobs in the SAME repo/branch use identical\n")
    report.append("workflow + cluster_profile combinations.\n\n")
    report.append("These MAY be intentional (different test suites, env vars) or\n")
    report.append("could potentially be consolidated.\n\n")

    workflow_dups = analyze_same_workflow_same_branch(jobs)
    if workflow_dups:
        report.append(f"Found {len(workflow_dups)} cases of workflow duplication.\n\n")
        report.append("| Org/Repo | Branch | Workflow | Jobs |\n")
        report.append("|----------|--------|----------|------|\n")
        for dup in sorted(workflow_dups,
                          key=lambda x: x['job_count'], reverse=True)[:20]:
            jobs_str = ', '.join(dup['jobs'][:3])
            if len(dup['jobs']) > 3:
                jobs_str += f" (+{len(dup['jobs'])-3} more)"
            report.append(
                f"| {dup['org']}/{dup['repo']} | {dup['branch']} | "
                f"{dup['workflow']} | {jobs_str} |\n"
            )
    else:
        report.append("No workflow duplications found.\n")

    # Presubmit Trigger Analysis
    report.append("\n## 2. Presubmit Trigger Analysis\n")
    triggers = analyze_presubmit_triggers(jobs)

    report.append(f"\n### Trigger Pattern Summary\n\n")
    report.append("| Pattern | Count | % of Presubmits |\n")
    report.append("|---------|-------|------------------|\n")

    total_presubmit = sum(len(v) for v in triggers.values())
    for pattern, jobs_list in triggers.items():
        pct = len(jobs_list) / total_presubmit * 100 if total_presubmit else 0
        report.append(f"| {pattern} | {len(jobs_list)} | {pct:.1f}% |\n")

    # Always run without throttle is concerning
    if triggers['always_run_no_throttle']:
        report.append("\n### Always Run Jobs Without Throttling\n")
        report.append("These run on every PR without minimum_interval.\n\n")
        by_repo = defaultdict(list)
        for job in triggers['always_run_no_throttle']:
            by_repo[(job['org'], job['repo'])].append(job)

        report.append("| Org/Repo | Jobs |\n")
        report.append("|----------|------|\n")
        for (org, repo), jobs_list in sorted(by_repo.items()):
            job_names = ', '.join(set(j['job_name'] for j in jobs_list))[:60]
            report.append(f"| {org}/{repo} | {job_names} |\n")

    # Branch Consistency
    report.append("\n## 3. Branch Coverage Inconsistencies\n")
    report.append("Jobs present on some branches but missing from others.\n\n")

    inconsistencies = analyze_branch_consistency(jobs)
    if inconsistencies:
        # Filter to significant inconsistencies (missing recent releases)
        significant = [i for i in inconsistencies
                       if any('release-4.2' in b or 'main' in b or 'master' in b
                              for b in i['missing_branches'])]

        report.append(f"Found {len(significant)} significant inconsistencies.\n\n")

        if significant:
            report.append("| Org/Repo | Job | Missing Branches |\n")
            report.append("|----------|-----|------------------|\n")
            for inc in significant[:30]:
                missing = ', '.join(inc['missing_branches'][:3])
                if len(inc['missing_branches']) > 3:
                    missing += f" (+{len(inc['missing_branches'])-3})"
                report.append(
                    f"| {inc['org']}/{inc['repo']} | {inc['job_name']} | {missing} |\n"
                )
    else:
        report.append("No significant inconsistencies found.\n")

    # Consolidation Opportunities
    report.append("\n## 4. Recommendations\n\n")

    report.append("### Review Items\n\n")

    if workflow_dups:
        report.append("1. **Same workflow+cluster jobs**: Review jobs using identical\n")
        report.append("   workflow+cluster in the same repo/branch. These may have\n")
        report.append("   different env vars or test suites, but could potentially\n")
        report.append("   be consolidated if testing overlapping functionality.\n")
        report.append(f"   - Cases to review: {len(workflow_dups)}\n\n")

    report.append("2. **Always-run jobs**: Review jobs marked `always_run: true` "
                  "without `minimum_interval` throttling.\n")
    report.append(f"   - Jobs to review: {len(triggers['always_run_no_throttle'])}\n\n")

    report.append("3. **Branch inconsistencies**: Consider adding missing jobs "
                  "to recent release branches for consistent coverage.\n")
    report.append(f"   - Inconsistencies found: {len(inconsistencies)}\n")

    # Write report
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(''.join(report))

    print(f"Report written to {output_file}", file=sys.stderr)

    # Also write machine-readable data
    json_output = output_file.replace('.md', '_data.json')
    with open(json_output, 'w', encoding='utf-8') as f:
        json.dump({
            'same_workflow_same_branch': workflow_dups,
            'trigger_analysis': {k: len(v) for k, v in triggers.items()},
            'branch_inconsistencies': inconsistencies[:100],
        }, f, indent=2)

    print(f"Data written to {json_output}", file=sys.stderr)


def main():
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(
        description="Analyze OpenStack CI jobs for redundancy"
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
    print("OpenStack CI Redundancy Analysis")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print()

    inventory_path = os.path.join(output_dir, args.inventory)
    output_path = os.path.join(output_dir, "redundant_jobs_report.md")

    jobs = load_inventory(inventory_path)
    generate_report(jobs, output_path)


if __name__ == "__main__":
    main()
