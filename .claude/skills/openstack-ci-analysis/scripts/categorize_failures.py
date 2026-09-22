#!/usr/bin/env python3
"""
Categorize job failures using heuristic classification.
Categories: Infrastructure, Flaky, Product Bug, Unknown/Needs Triage
"""

import argparse
import json
import os
import sys
from datetime import datetime
from collections import defaultdict

RELEASES = ["4.17", "4.18", "4.19", "4.20", "4.21", "4.22"]

# Will be set by parse_args()
OUTPUT_DIR = None


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Categorize job failures using heuristic classification"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for input/output files (default: script directory)"
    )
    return parser.parse_args()


def load_extended_metrics():
    """Load extended metrics data."""
    filepath = os.path.join(OUTPUT_DIR, "extended_metrics.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_extended_jobs():
    """Load extended metrics per job."""
    filepath = os.path.join(OUTPUT_DIR, "extended_metrics_jobs.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_sippy_data():
    """Load raw Sippy data for additional context."""
    filepath = os.path.join(OUTPUT_DIR, "sippy_jobs_raw.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def categorize_job(job):
    """
    Categorize a job failure based on heuristics.

    Categories:
    - infrastructure: Likely infrastructure/provisioning issues
    - flaky: Inconsistent pass rates (30-70%)
    - product_bug: Consistent failures with bugs filed
    - needs_triage: Unknown, requires investigation
    """
    name = job.get("name", "").lower()
    brief_name = job.get("brief_name", "").lower()
    combined_rate = job.get("combined_pass_rate")
    current_rate = job.get("current_pass_rate")
    open_bugs = job.get("open_bugs", 0)
    combined_runs = job.get("combined_runs", 0)
    trend = job.get("trend", "")

    # Skip jobs with no data
    if combined_rate is None or combined_runs < 2:
        return None, "insufficient_data"

    # Jobs at or above 80% are not problem jobs
    if combined_rate >= 80:
        return None, "passing"

    # Category determination heuristics

    # 1. Product Bug: 0% pass rate or very low with bugs filed
    if combined_rate == 0:
        if open_bugs > 0:
            return "product_bug", "0% pass rate with filed bugs"
        else:
            return "needs_triage", "0% pass rate, no bugs filed"

    # 2. Infrastructure indicators
    infra_keywords = [
        "install", "provision", "bootstrap", "create",
        "vpc", "network", "dns", "loadbalancer", "lb",
    ]
    is_infra_job = any(kw in name or kw in brief_name for kw in infra_keywords)

    if combined_rate < 30 and is_infra_job:
        return "infrastructure", "Low pass rate on infrastructure-related job"

    # 3. Flaky: 30-70% pass rate (inconsistent)
    if 30 <= combined_rate < 70:
        if trend == "degrading":
            return "flaky", "Inconsistent pass rate, trending worse"
        elif trend == "improving":
            return "flaky", "Inconsistent pass rate, trending better"
        else:
            return "flaky", "Inconsistent pass rate (30-70%)"

    # 4. Product Bug: Low pass rate with bugs
    if combined_rate < 50 and open_bugs > 0:
        return "product_bug", f"Low pass rate with {open_bugs} open bug(s)"

    # 5. Check for specific failure patterns in job name
    if "etcd" in name or "scaling" in name:
        return "product_bug", "Known problematic component"

    if "techpreview" in name:
        return "needs_triage", "Tech preview feature - expected instability"

    # 6. Very low rate without bugs = needs investigation
    if combined_rate < 30:
        return "needs_triage", "Very low pass rate, needs investigation"

    # 7. Moderate failures (70-80%)
    if 70 <= combined_rate < 80:
        if trend == "degrading":
            return "needs_triage", "Recently degraded, needs investigation"
        else:
            return "flaky", "Borderline pass rate"

    # Default
    return "needs_triage", "Uncategorized failure"


def categorize_all_jobs(extended_jobs, sippy_data):
    """Categorize all problem jobs."""
    results = {
        "generated": datetime.now().isoformat(),
        "categories": {
            "infrastructure": [],
            "flaky": [],
            "product_bug": [],
            "needs_triage": [],
        },
        "summary": {},
        "by_release": defaultdict(lambda: defaultdict(list)),
    }

    # Build Sippy lookup for additional context
    sippy_bugs = {}
    if sippy_data:
        for release, jobs in sippy_data.get("jobs_by_release", {}).items():
            for job in jobs:
                sippy_bugs[job.get("name", "")] = job.get("open_bugs", 0)

    # Categorize each job
    for job in extended_jobs:
        # Ensure we have bug info
        if job.get("open_bugs") is None and job.get("name") in sippy_bugs:
            job["open_bugs"] = sippy_bugs[job.get("name")]

        category, reason = categorize_job(job)

        if category is None:
            continue

        job_info = {
            "release": job.get("release", ""),
            "name": job.get("name", ""),
            "brief_name": job.get("brief_name", ""),
            "combined_runs": job.get("combined_runs", 0),
            "combined_pass_rate": job.get("combined_pass_rate"),
            "current_pass_rate": job.get("current_pass_rate"),
            "open_bugs": job.get("open_bugs", 0),
            "trend": job.get("trend", ""),
            "reason": reason,
        }

        results["categories"][category].append(job_info)
        results["by_release"][job.get("release", "")][category].append(job_info)

    # Sort each category by pass rate
    for category in results["categories"]:
        results["categories"][category].sort(
            key=lambda x: x.get("combined_pass_rate") or 0
        )

    # Summary statistics
    total_problems = sum(len(jobs) for jobs in results["categories"].values())
    results["summary"] = {
        "total_problem_jobs": total_problems,
        "by_category": {
            cat: len(jobs) for cat, jobs in results["categories"].items()
        },
        "percentages": {},
    }

    if total_problems > 0:
        for cat, count in results["summary"]["by_category"].items():
            results["summary"]["percentages"][cat] = round(count / total_problems * 100, 1)

    return results


def generate_report(analysis):
    """Generate markdown report for failure categorization."""
    report = []
    report.append("# Failure Categorization Report")
    report.append("")
    report.append(f"**Generated:** {analysis['generated']}")
    report.append("")
    report.append("Jobs with pass rate below 80% are categorized by likely root cause.")
    report.append("")

    # Summary
    summary = analysis.get("summary", {})
    report.append("## Summary")
    report.append("")
    report.append(f"**Total Problem Jobs:** {summary.get('total_problem_jobs', 0)}")
    report.append("")
    report.append("| Category | Count | Percentage | Description |")
    report.append("|----------|-------|------------|-------------|")

    category_descriptions = {
        "infrastructure": "Provisioning/infra failures",
        "flaky": "Inconsistent (30-70% pass rate)",
        "product_bug": "Known bugs filed",
        "needs_triage": "Requires investigation",
    }

    by_cat = summary.get("by_category", {})
    percentages = summary.get("percentages", {})
    for cat in ["infrastructure", "flaky", "product_bug", "needs_triage"]:
        count = by_cat.get(cat, 0)
        pct = percentages.get(cat, 0)
        desc = category_descriptions.get(cat, "")
        report.append(f"| {cat.replace('_', ' ').title()} | {count} | {pct}% | {desc} |")
    report.append("")

    # Category breakdowns
    categories = analysis.get("categories", {})

    # Infrastructure issues
    infra = categories.get("infrastructure", [])
    if infra:
        report.append("## Infrastructure Issues")
        report.append("")
        report.append("Jobs likely failing due to OpenStack provisioning or infrastructure problems:")
        report.append("")
        report.append("| Release | Job | Pass Rate | Runs | Reason |")
        report.append("|---------|-----|-----------|------|--------|")
        for job in infra[:15]:
            rate = job.get("combined_pass_rate")
            rate_str = f"{rate:.1f}%" if rate is not None else "N/A"
            report.append(
                f"| {job['release']} | {job['brief_name'][:40]} | {rate_str} | "
                f"{job['combined_runs']} | {job['reason'][:30]} |"
            )
        if len(infra) > 15:
            report.append(f"| ... | *{len(infra) - 15} more* | | | |")
        report.append("")

    # Flaky jobs
    flaky = categories.get("flaky", [])
    if flaky:
        report.append("## Flaky Jobs")
        report.append("")
        report.append("Jobs with inconsistent pass rates (30-70%) indicating test or timing issues:")
        report.append("")
        report.append("| Release | Job | Pass Rate | Trend | Runs |")
        report.append("|---------|-----|-----------|-------|------|")
        for job in flaky[:15]:
            rate = job.get("combined_pass_rate")
            rate_str = f"{rate:.1f}%" if rate is not None else "N/A"
            trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(job["trend"], "")
            report.append(
                f"| {job['release']} | {job['brief_name'][:40]} | {rate_str} | "
                f"{trend_icon} | {job['combined_runs']} |"
            )
        if len(flaky) > 15:
            report.append(f"| ... | *{len(flaky) - 15} more* | | | |")
        report.append("")

    # Product bugs
    bugs = categories.get("product_bug", [])
    if bugs:
        report.append("## Product Bugs")
        report.append("")
        report.append("Jobs with known bugs filed - track via bug system:")
        report.append("")
        report.append("| Release | Job | Pass Rate | Open Bugs | Runs |")
        report.append("|---------|-----|-----------|-----------|------|")
        for job in bugs[:15]:
            rate = job.get("combined_pass_rate")
            rate_str = f"{rate:.1f}%" if rate is not None else "N/A"
            report.append(
                f"| {job['release']} | {job['brief_name'][:40]} | {rate_str} | "
                f"{job['open_bugs']} | {job['combined_runs']} |"
            )
        if len(bugs) > 15:
            report.append(f"| ... | *{len(bugs) - 15} more* | | | |")
        report.append("")

    # Needs triage
    triage = categories.get("needs_triage", [])
    if triage:
        report.append("## Needs Triage")
        report.append("")
        report.append("Jobs requiring investigation to determine root cause:")
        report.append("")
        report.append("| Release | Job | Pass Rate | Runs | Reason |")
        report.append("|---------|-----|-----------|------|--------|")
        for job in triage[:15]:
            rate = job.get("combined_pass_rate")
            rate_str = f"{rate:.1f}%" if rate is not None else "N/A"
            report.append(
                f"| {job['release']} | {job['brief_name'][:40]} | {rate_str} | "
                f"{job['combined_runs']} | {job['reason'][:30]} |"
            )
        if len(triage) > 15:
            report.append(f"| ... | *{len(triage) - 15} more* | | | |")
        report.append("")

    # Recommendations
    report.append("## Recommended Actions by Category")
    report.append("")
    report.append("### Infrastructure")
    report.append("- Review OpenStack cloud health and quotas")
    report.append("- Check for recurring provisioning failures")
    report.append("- Validate network and DNS configuration")
    report.append("")
    report.append("### Flaky")
    report.append("- Analyze test logs for timing-related failures")
    report.append("- Consider adding retries for known flaky operations")
    report.append("- Investigate environmental dependencies")
    report.append("")
    report.append("### Product Bug")
    report.append("- Track existing bugs to resolution")
    report.append("- Prioritize bugs blocking multiple jobs")
    report.append("- Consider disabling jobs until bug is fixed")
    report.append("")
    report.append("### Needs Triage")
    report.append("- Review recent job logs to identify patterns")
    report.append("- File bugs with failure details")
    report.append("- Categorize after investigation")
    report.append("")

    report.append("---")
    report.append("")
    report.append("*Classification based on heuristics - manual review recommended*")
    report.append("*Data Source: [Sippy](https://sippy.dptools.openshift.org/)*")
    report.append("")

    return "\n".join(report)


def main():
    global OUTPUT_DIR
    args = parse_args()
    OUTPUT_DIR = os.path.abspath(args.output_dir)

    print("=" * 60)
    print("OpenStack CI Failure Categorization")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Load data
    extended_jobs = load_extended_jobs()
    if not extended_jobs:
        print("Error: No extended metrics jobs data found.")
        print("Run fetch_extended_metrics.py first.")
        sys.exit(1)
    print(f"Loaded {len(extended_jobs)} jobs")

    sippy_data = load_sippy_data()
    print(f"Sippy data loaded: {sippy_data is not None}")
    print()

    # Categorize
    analysis = categorize_all_jobs(extended_jobs, sippy_data)

    # Convert defaultdict to regular dict for JSON serialization
    analysis["by_release"] = {k: dict(v) for k, v in analysis["by_release"].items()}

    # Save results
    analysis_path = os.path.join(OUTPUT_DIR, "failure_categories.json")
    with open(analysis_path, 'w') as f:
        json.dump(analysis, f, indent=2)
    print(f"Saved: {analysis_path}")

    # Generate report
    report = generate_report(analysis)
    report_path = os.path.join(OUTPUT_DIR, "failure_categories_report.md")
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"Saved: {report_path}")

    # Print summary
    print()
    print("=" * 60)
    print("Summary:")
    summary = analysis.get("summary", {})
    print(f"  Total problem jobs: {summary.get('total_problem_jobs', 0)}")
    for cat, count in summary.get("by_category", {}).items():
        pct = summary.get("percentages", {}).get(cat, 0)
        print(f"  {cat}: {count} ({pct}%)")
    print("=" * 60)


if __name__ == "__main__":
    main()
