#!/usr/bin/env python3
"""
Analyze OpenStack CI job triggers for optimization opportunities.

This script identifies:
1. Jobs missing file-change filters (skip_if_only_changed, run_if_changed)
2. Always-run jobs without throttling
3. Repos that could benefit from smarter triggering
4. Recommended patterns for skip_if_only_changed
"""

import argparse
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path


# Common patterns for files that typically don't need E2E tests
SKIP_PATTERNS = {
    'documentation': [
        r'^docs/',
        r'\.md$',
        r'^README',
    ],
    'ownership': [
        r'(^|/)OWNERS(_ALIASES)?$',
    ],
    'github_config': [
        r'^\.github/',
    ],
    'general': [
        r'^CHANGELOG',
        r'^LICENSE',
        r'^DCO',
        r'^SECURITY\.md$',
    ],
}

# Suggested skip pattern for E2E tests
SUGGESTED_SKIP_PATTERN = r'(^docs/)|(\\.md$)|((^|/)OWNERS(_ALIASES)?$)'


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


def analyze_trigger_patterns(jobs):
    """
    Analyze the current trigger patterns used across jobs.
    """
    patterns = {
        'has_skip_if_only_changed': [],
        'has_run_if_changed': [],
        'has_minimum_interval': [],
        'always_run_true': [],
        'optional_true': [],
        'no_filters': [],  # Jobs with no trigger optimization
    }

    for job in jobs:
        if job['skip_if_only_changed']:
            patterns['has_skip_if_only_changed'].append(job)
        if job['run_if_changed']:
            patterns['has_run_if_changed'].append(job)
        if job['minimum_interval']:
            patterns['has_minimum_interval'].append(job)
        if job['always_run']:
            patterns['always_run_true'].append(job)
        if job['optional']:
            patterns['optional_true'].append(job)

        # Jobs that could benefit from trigger optimization
        if (job['job_type'] == 'presubmit' and
            not job['skip_if_only_changed'] and
            not job['run_if_changed'] and
            not job['optional']):
            patterns['no_filters'].append(job)

    return patterns


def group_jobs_by_repo(jobs):
    """Group jobs by org/repo for analysis."""
    repos = defaultdict(list)
    for job in jobs:
        key = (job['org'], job['repo'])
        repos[key].append(job)
    return repos


def analyze_repo_trigger_status(repos):
    """
    For each repo, determine if it would benefit from skip_if_only_changed.
    """
    repo_analysis = []

    for (org, repo), jobs in repos.items():
        presubmit_jobs = [j for j in jobs if j['job_type'] == 'presubmit']

        if not presubmit_jobs:
            continue

        # Count jobs with/without filters
        with_skip = len([j for j in presubmit_jobs if j['skip_if_only_changed']])
        with_run_if = len([j for j in presubmit_jobs if j['run_if_changed']])
        optional = len([j for j in presubmit_jobs if j['optional']])
        always_run = len([j for j in presubmit_jobs if j['always_run']])
        no_filter = len([j for j in presubmit_jobs
                         if not j['skip_if_only_changed']
                         and not j['run_if_changed']
                         and not j['optional']])

        # Determine if repo could benefit
        could_benefit = no_filter > 0 and with_skip == 0

        repo_analysis.append({
            'org': org,
            'repo': repo,
            'total_presubmit': len(presubmit_jobs),
            'with_skip_pattern': with_skip,
            'with_run_if_changed': with_run_if,
            'optional': optional,
            'always_run': always_run,
            'no_filter': no_filter,
            'could_benefit': could_benefit,
            'job_names': sorted(set(j['job_name'] for j in presubmit_jobs)),
        })

    return repo_analysis


def analyze_always_run_jobs(jobs):
    """
    Find jobs that are always_run=true without throttling.
    These run on every PR and should be reviewed.
    """
    always_run_jobs = [j for j in jobs
                       if j['always_run'] and j['job_type'] == 'presubmit']

    # Group by whether they have minimum_interval
    with_throttle = [j for j in always_run_jobs if j['minimum_interval']]
    without_throttle = [j for j in always_run_jobs if not j['minimum_interval']]

    return {
        'with_throttle': with_throttle,
        'without_throttle': without_throttle,
    }


def analyze_periodic_schedules(jobs):
    """
    Analyze periodic job schedules for optimization.
    """
    periodic_jobs = [j for j in jobs if j['job_type'] == 'periodic']

    # Group by schedule pattern
    schedules = defaultdict(list)
    for job in periodic_jobs:
        schedules[job['schedule']].append(job)

    return schedules


def generate_report(jobs, output_file):
    """Generate comprehensive trigger optimization report."""
    report = []
    report.append("# OpenStack CI Trigger Optimization Report\n")
    report.append(f"Total jobs analyzed: {len(jobs)}\n")

    presubmit_jobs = [j for j in jobs if j['job_type'] == 'presubmit']
    periodic_jobs = [j for j in jobs if j['job_type'] == 'periodic']

    report.append(f"- Presubmit jobs: {len(presubmit_jobs)}\n")
    report.append(f"- Periodic jobs: {len(periodic_jobs)}\n")

    # Trigger Pattern Analysis
    report.append("\n## 1. Current Trigger Pattern Usage\n\n")
    patterns = analyze_trigger_patterns(jobs)

    report.append("| Pattern | Count | % of Presubmits |\n")
    report.append("|---------|-------|------------------|\n")

    total_pre = len(presubmit_jobs)
    for pattern, pattern_jobs in patterns.items():
        count = len([j for j in pattern_jobs if j['job_type'] == 'presubmit'])
        pct = count / total_pre * 100 if total_pre else 0
        report.append(f"| {pattern} | {count} | {pct:.1f}% |\n")

    # Jobs Missing Filters
    report.append("\n## 2. Jobs Without Trigger Optimization\n")
    report.append("Presubmit jobs without skip_if_only_changed, "
                  "run_if_changed, or optional flags.\n\n")

    no_filter_jobs = patterns['no_filters']
    if no_filter_jobs:
        # Group by repo
        by_repo = defaultdict(list)
        for job in no_filter_jobs:
            by_repo[(job['org'], job['repo'])].append(job)

        report.append(f"Found {len(no_filter_jobs)} jobs across "
                      f"{len(by_repo)} repositories that could benefit from "
                      f"trigger optimization.\n\n")

        report.append("| Org/Repo | Jobs Without Filters | Job Names |\n")
        report.append("|----------|----------------------|-----------|\n")

        for (org, repo), repo_jobs in sorted(by_repo.items(),
                                              key=lambda x: len(x[1]),
                                              reverse=True)[:20]:
            names = ', '.join(set(j['job_name'] for j in repo_jobs))[:50]
            if len(names) >= 50:
                names += "..."
            report.append(f"| {org}/{repo} | {len(repo_jobs)} | {names} |\n")
    else:
        report.append("All presubmit jobs have some form of trigger optimization.\n")

    # Repository Analysis
    report.append("\n## 3. Repository Trigger Analysis\n")
    report.append("Repositories that could benefit from adding "
                  "`skip_if_only_changed` patterns.\n\n")

    repos = group_jobs_by_repo(jobs)
    repo_analysis = analyze_repo_trigger_status(repos)

    # Filter to repos that could benefit
    could_benefit = [r for r in repo_analysis if r['could_benefit']]

    if could_benefit:
        report.append(f"Found {len(could_benefit)} repositories that could "
                      f"add skip patterns.\n\n")

        report.append("| Org/Repo | Presubmits | No Filter | Suggested Action |\n")
        report.append("|----------|------------|-----------|------------------|\n")

        for repo in sorted(could_benefit,
                           key=lambda x: x['no_filter'], reverse=True)[:25]:
            action = f"Add skip_if_only_changed to {repo['no_filter']} jobs"
            report.append(
                f"| {repo['org']}/{repo['repo']} | {repo['total_presubmit']} | "
                f"{repo['no_filter']} | {action} |\n"
            )
    else:
        report.append("All repositories have adequate trigger patterns.\n")

    # Suggested Skip Pattern
    report.append("\n## 4. Recommended skip_if_only_changed Patterns\n\n")
    report.append("For OpenStack E2E tests, we recommend:\n\n")
    report.append("```yaml\n")
    report.append("skip_if_only_changed: ")
    report.append(f"{SUGGESTED_SKIP_PATTERN}\n")
    report.append("```\n\n")

    report.append("This pattern skips the job when changes only affect:\n")
    report.append("- Documentation files (`docs/` directory)\n")
    report.append("- Markdown files (`*.md`)\n")
    report.append("- OWNERS files\n\n")

    report.append("### Individual Component Patterns\n\n")
    for category, patterns_list in SKIP_PATTERNS.items():
        report.append(f"**{category}:**\n")
        for p in patterns_list:
            report.append(f"- `{p}`\n")
        report.append("\n")

    # Periodic Schedule Analysis
    report.append("\n## 5. Periodic Job Schedule Analysis\n\n")
    schedules = analyze_periodic_schedules(jobs)

    if schedules:
        report.append("| Schedule | Jobs | Examples |\n")
        report.append("|----------|------|----------|\n")

        for schedule, sched_jobs in sorted(schedules.items()):
            examples = ', '.join(set(j['job_name'] for j in sched_jobs))[:40]
            if len(examples) >= 40:
                examples += "..."
            report.append(f"| {schedule} | {len(sched_jobs)} | {examples} |\n")
    else:
        report.append("No periodic jobs found.\n")

    # Optimization Recommendations
    report.append("\n## 6. Optimization Recommendations\n\n")

    report.append("### High Impact\n\n")

    if could_benefit:
        report.append(f"1. **Add skip_if_only_changed to {len(could_benefit)} repos**: "
                      f"Approximately {sum(r['no_filter'] for r in could_benefit)} jobs "
                      f"could skip runs on docs-only PRs.\n\n")

    # Calculate potential savings
    total_no_filter = len(patterns['no_filters'])
    report.append(f"2. **Total presubmit jobs without filters**: {total_no_filter}\n")
    report.append("   These jobs run on every non-optional PR regardless of "
                  "which files changed.\n\n")

    report.append("### Medium Impact\n\n")
    report.append("3. **Review always_run jobs**: Ensure jobs marked `always_run: true` "
                  "are truly required for every PR.\n\n")

    report.append("4. **Add minimum_interval to high-frequency jobs**: "
                  "Throttle jobs that don't need to run on every commit.\n\n")

    report.append("### Implementation Steps\n\n")
    report.append("1. For each repo without skip patterns:\n")
    report.append("   - Identify which test jobs are full E2E (vs unit tests)\n")
    report.append("   - Add `skip_if_only_changed` to E2E tests\n")
    report.append("   - Keep unit tests running on all changes\n\n")

    report.append("2. Example config change:\n")
    report.append("```yaml\n")
    report.append("tests:\n")
    report.append("- as: e2e-openstack\n")
    report.append("  skip_if_only_changed: (^docs/)|(\\\\..md$)|((^|/)OWNERS$)\n")
    report.append("  steps:\n")
    report.append("    cluster_profile: openstack-vexxhost\n")
    report.append("    workflow: openshift-e2e-openstack-ipi\n")
    report.append("```\n")

    # Write report
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(''.join(report))

    print(f"Report written to {output_file}", file=sys.stderr)

    # Also write machine-readable data
    json_output = output_file.replace('.md', '_data.json')
    with open(json_output, 'w', encoding='utf-8') as f:
        json.dump({
            'trigger_patterns': {k: len(v) for k, v in patterns.items()},
            'repos_without_skip': [
                {
                    'org': r['org'],
                    'repo': r['repo'],
                    'jobs_without_filter': r['no_filter'],
                    'job_names': r['job_names'],
                }
                for r in could_benefit
            ],
            'jobs_without_filter': [
                {
                    'org': j['org'],
                    'repo': j['repo'],
                    'branch': j['branch'],
                    'job_name': j['job_name'],
                }
                for j in patterns['no_filters']
            ],
            'periodic_schedules': {k: len(v) for k, v in schedules.items()},
            'suggested_pattern': SUGGESTED_SKIP_PATTERN,
        }, f, indent=2)

    print(f"Data written to {json_output}", file=sys.stderr)


def main():
    import os
    script_dir = os.path.dirname(os.path.abspath(__file__))

    parser = argparse.ArgumentParser(
        description="Analyze OpenStack CI job triggers for optimization"
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
    print("OpenStack CI Trigger Optimization Analysis")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print()

    inventory_path = os.path.join(output_dir, args.inventory)
    output_path = os.path.join(output_dir, "trigger_optimization_report.md")

    jobs = load_inventory(inventory_path)
    generate_report(jobs, output_path)


if __name__ == "__main__":
    main()
