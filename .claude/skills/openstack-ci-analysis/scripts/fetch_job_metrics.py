#!/usr/bin/env python3
"""
Fetch job metrics (pass rates, run counts) from Sippy API for OpenStack CI jobs.
Saves progress to files to allow resumption if interrupted.
"""

import argparse
import json
import os
import sys
import time
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
from datetime import datetime

SIPPY_BASE = "https://sippy.dptools.openshift.org/api"
RELEASES = ["4.17", "4.18", "4.19", "4.20", "4.21", "4.22"]

# Will be set by parse_args()
OUTPUT_DIR = None


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Fetch job metrics from Sippy API for OpenStack CI jobs"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for output files (default: script directory)"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Refetch data even if cache exists"
    )
    return parser.parse_args()

def fetch_json(url, retries=3, delay=2):
    """Fetch JSON from URL with retries."""
    for attempt in range(retries):
        try:
            req = Request(url, headers={"User-Agent": "OpenStack-CI-Analysis/1.0"})
            with urlopen(req, timeout=60) as response:
                return json.loads(response.read().decode())
        except (URLError, HTTPError) as e:
            print(f"  Attempt {attempt + 1} failed: {e}")
            if attempt < retries - 1:
                time.sleep(delay)
    return None

def fetch_openstack_jobs_for_release(release):
    """Fetch all OpenStack jobs for a specific release."""
    url = f"{SIPPY_BASE}/jobs?release={release}"
    print(f"Fetching jobs for release {release}...")

    data = fetch_json(url)
    if data is None:
        print(f"  Failed to fetch data for {release}")
        return []

    # Filter for OpenStack jobs
    openstack_jobs = [j for j in data if "openstack" in j.get("name", "").lower()]
    print(f"  Found {len(openstack_jobs)} OpenStack jobs out of {len(data)} total")

    return openstack_jobs

def save_progress(data, filename):
    """Save data to file."""
    filepath = os.path.join(OUTPUT_DIR, filename)
    with open(filepath, 'w') as f:
        json.dump(data, f, indent=2)
    print(f"Saved: {filepath}")

def load_progress(filename):
    """Load data from file if exists."""
    filepath = os.path.join(OUTPUT_DIR, filename)
    if os.path.exists(filepath):
        with open(filepath, 'r') as f:
            return json.load(f)
    return None

def analyze_job_metrics(all_jobs_by_release):
    """Analyze and summarize job metrics."""
    summary = {
        "generated": datetime.now().isoformat(),
        "releases": {},
        "overall_stats": {},
        "worst_jobs": [],
        "best_jobs": [],
        "jobs_by_pass_rate": {}
    }

    all_jobs_flat = []

    for release, jobs in all_jobs_by_release.items():
        if not jobs:
            continue

        release_stats = {
            "total_jobs": len(jobs),
            "total_runs": sum(j.get("current_runs", 0) for j in jobs),
            "total_passes": sum(j.get("current_passes", 0) for j in jobs),
            "avg_pass_rate": 0,
            "jobs_below_90": 0,
            "jobs_below_80": 0,
            "jobs_below_50": 0,
        }

        pass_rates = []
        for job in jobs:
            rate = job.get("current_pass_percentage", 0)
            pass_rates.append(rate)
            if rate < 90:
                release_stats["jobs_below_90"] += 1
            if rate < 80:
                release_stats["jobs_below_80"] += 1
            if rate < 50:
                release_stats["jobs_below_50"] += 1

            # Add to flat list for overall analysis
            all_jobs_flat.append({
                "release": release,
                "name": job.get("name", ""),
                "brief_name": job.get("brief_name", ""),
                "pass_rate": rate,
                "runs": job.get("current_runs", 0),
                "passes": job.get("current_passes", 0),
                "previous_pass_rate": job.get("previous_pass_percentage", 0),
                "improvement": job.get("net_improvement", 0),
                "last_pass": job.get("last_pass", ""),
                "open_bugs": job.get("open_bugs", 0),
            })

        if pass_rates:
            release_stats["avg_pass_rate"] = sum(pass_rates) / len(pass_rates)

        summary["releases"][release] = release_stats

    # Find worst and best performing jobs
    jobs_with_runs = [j for j in all_jobs_flat if j["runs"] > 0]
    if jobs_with_runs:
        # Worst jobs (lowest pass rate with at least 2 runs)
        jobs_with_sufficient_runs = [j for j in jobs_with_runs if j["runs"] >= 2]
        summary["worst_jobs"] = sorted(jobs_with_sufficient_runs, key=lambda x: x["pass_rate"])[:20]

        # Best jobs (100% pass rate with most runs)
        perfect_jobs = [j for j in jobs_with_runs if j["pass_rate"] == 100]
        summary["best_jobs"] = sorted(perfect_jobs, key=lambda x: -x["runs"])[:20]

        # Group by pass rate ranges
        ranges = {
            "100%": [j for j in jobs_with_runs if j["pass_rate"] == 100],
            "90-99%": [j for j in jobs_with_runs if 90 <= j["pass_rate"] < 100],
            "80-89%": [j for j in jobs_with_runs if 80 <= j["pass_rate"] < 90],
            "50-79%": [j for j in jobs_with_runs if 50 <= j["pass_rate"] < 80],
            "below_50%": [j for j in jobs_with_runs if j["pass_rate"] < 50],
        }
        summary["jobs_by_pass_rate"] = {k: len(v) for k, v in ranges.items()}

    # Overall stats
    if all_jobs_flat:
        all_runs = sum(j["runs"] for j in all_jobs_flat)
        all_passes = sum(j["passes"] for j in all_jobs_flat)
        summary["overall_stats"] = {
            "total_jobs": len(all_jobs_flat),
            "total_runs": all_runs,
            "total_passes": all_passes,
            "overall_pass_rate": (all_passes / all_runs * 100) if all_runs > 0 else 0,
        }

    return summary, all_jobs_flat

def generate_metrics_report(summary, all_jobs):
    """Generate a markdown report of job metrics."""
    report = []
    report.append("# OpenStack CI Job Metrics Report")
    report.append("")
    report.append(f"**Generated:** {summary['generated']}")
    report.append("")

    # Overall stats
    report.append("## Overall Statistics")
    report.append("")
    stats = summary.get("overall_stats", {})
    report.append(f"| Metric | Value |")
    report.append(f"|--------|-------|")
    report.append(f"| Total OpenStack Jobs Tracked | {stats.get('total_jobs', 0)} |")
    report.append(f"| Total Job Runs (current period) | {stats.get('total_runs', 0)} |")
    report.append(f"| Total Passes | {stats.get('total_passes', 0)} |")
    report.append(f"| Overall Pass Rate | {stats.get('overall_pass_rate', 0):.1f}% |")
    report.append("")

    # Pass rate distribution
    report.append("## Pass Rate Distribution")
    report.append("")
    report.append("| Pass Rate Range | Job Count |")
    report.append("|-----------------|-----------|")
    for range_name, count in summary.get("jobs_by_pass_rate", {}).items():
        report.append(f"| {range_name} | {count} |")
    report.append("")

    # By release
    report.append("## Metrics by Release")
    report.append("")
    report.append("| Release | Jobs | Total Runs | Avg Pass Rate | <90% | <80% | <50% |")
    report.append("|---------|------|------------|---------------|------|------|------|")
    for release in RELEASES:
        rel_stats = summary.get("releases", {}).get(release, {})
        if rel_stats:
            report.append(f"| {release} | {rel_stats.get('total_jobs', 0)} | {rel_stats.get('total_runs', 0)} | {rel_stats.get('avg_pass_rate', 0):.1f}% | {rel_stats.get('jobs_below_90', 0)} | {rel_stats.get('jobs_below_80', 0)} | {rel_stats.get('jobs_below_50', 0)} |")
    report.append("")

    # Worst performing jobs
    report.append("## Worst Performing Jobs (by pass rate)")
    report.append("")
    report.append("Jobs with at least 2 runs, sorted by lowest pass rate:")
    report.append("")
    report.append("| Release | Job Name | Pass Rate | Runs | Passes |")
    report.append("|---------|----------|-----------|------|--------|")
    for job in summary.get("worst_jobs", [])[:15]:
        report.append(f"| {job['release']} | {job['brief_name'][:60]} | {job['pass_rate']:.1f}% | {job['runs']} | {job['passes']} |")
    report.append("")

    # Best performing jobs with high volume
    report.append("## Best Performing Jobs (100% pass rate, most runs)")
    report.append("")
    report.append("| Release | Job Name | Runs | Last Pass |")
    report.append("|---------|----------|------|-----------|")
    for job in summary.get("best_jobs", [])[:10]:
        last_pass = job['last_pass'][:10] if job['last_pass'] else "N/A"
        report.append(f"| {job['release']} | {job['brief_name'][:60]} | {job['runs']} | {last_pass} |")
    report.append("")

    # Jobs needing attention
    report.append("## Jobs Needing Attention")
    report.append("")
    attention_jobs = [j for j in all_jobs if j["pass_rate"] < 80 and j["runs"] >= 2]
    if attention_jobs:
        report.append(f"**{len(attention_jobs)} jobs** have pass rate below 80%:")
        report.append("")
        for job in sorted(attention_jobs, key=lambda x: x["pass_rate"]):
            report.append(f"- **{job['brief_name']}** ({job['release']}): {job['pass_rate']:.1f}% ({job['passes']}/{job['runs']} runs)")
    else:
        report.append("All jobs with sufficient runs have pass rate >= 80%.")
    report.append("")

    # Data source
    report.append("---")
    report.append("")
    report.append("*Data Source: Sippy (https://sippy.dptools.openshift.org/)*")
    report.append("")

    return "\n".join(report)

def main():
    global OUTPUT_DIR
    args = parse_args()
    OUTPUT_DIR = os.path.abspath(args.output_dir)

    # Create output directory if needed
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 60)
    print("OpenStack CI Job Metrics Collector")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Check for existing progress
    progress_file = "sippy_jobs_raw.json"
    existing_data = load_progress(progress_file)

    if existing_data and not args.force:
        print(f"Found existing data from {existing_data.get('fetched_at', 'unknown')}")
        print("Use --force to refetch")
        all_jobs_by_release = existing_data.get("jobs_by_release", {})
    else:
        all_jobs_by_release = {}

        for release in RELEASES:
            jobs = fetch_openstack_jobs_for_release(release)
            all_jobs_by_release[release] = jobs

            # Save progress after each release
            save_progress({
                "fetched_at": datetime.now().isoformat(),
                "releases_fetched": list(all_jobs_by_release.keys()),
                "jobs_by_release": all_jobs_by_release
            }, progress_file)

            time.sleep(1)  # Be nice to the API

    print()
    print("Analyzing metrics...")
    summary, all_jobs = analyze_job_metrics(all_jobs_by_release)

    # Save summary
    save_progress(summary, "job_metrics_summary.json")
    save_progress(all_jobs, "job_metrics_all_jobs.json")

    # Generate report
    report = generate_metrics_report(summary, all_jobs)
    report_path = os.path.join(OUTPUT_DIR, "job_metrics_report.md")
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"Report saved: {report_path}")

    print()
    print("=" * 60)
    print("Summary:")
    print(f"  Total jobs: {summary['overall_stats'].get('total_jobs', 0)}")
    print(f"  Total runs: {summary['overall_stats'].get('total_runs', 0)}")
    print(f"  Overall pass rate: {summary['overall_stats'].get('overall_pass_rate', 0):.1f}%")
    print("=" * 60)

if __name__ == "__main__":
    main()
