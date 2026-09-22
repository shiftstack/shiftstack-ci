#!/usr/bin/env python3
"""
Fetch extended job metrics from Sippy API for OpenStack CI jobs.
Combines current + previous periods for ~14 day coverage.
Estimates job duration based on workflow/cluster profile.
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from urllib.request import urlopen, Request
from urllib.error import URLError, HTTPError
import time

SIPPY_BASE = "https://sippy.dptools.openshift.org/api"
RELEASES = ["4.17", "4.18", "4.19", "4.20", "4.21", "4.22"]

# Will be set by parse_args()
OUTPUT_DIR = None


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Calculate extended job metrics from Sippy data"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for input/output files (default: script directory)"
    )
    return parser.parse_args()

# Estimated durations by cluster profile (based on typical run times)
DURATION_ESTIMATES = {
    "openstack-vexxhost": {"min": 60, "typical": 90, "max": 150},
    "openstack-vh-mecha-central": {"min": 60, "typical": 90, "max": 150},
    "openstack-vh-mecha-az0": {"min": 60, "typical": 100, "max": 180},
    "openstack-nfv": {"min": 90, "typical": 120, "max": 200},
    "openstack-hwoffload": {"min": 90, "typical": 120, "max": 200},
    "openstack-vh-bm-rhos": {"min": 120, "typical": 180, "max": 300},
}


def load_collected_data():
    """Load previously collected Sippy data."""
    filepath = os.path.join(OUTPUT_DIR, "sippy_jobs_raw.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_job_inventory():
    """Load job inventory for cluster profile info."""
    filepath = os.path.join(OUTPUT_DIR, "openstack_jobs_inventory.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def calculate_extended_metrics(sippy_data, inventory):
    """Calculate extended metrics combining current + previous periods."""

    results = {
        "generated": datetime.now().isoformat(),
        "period": "~14 days (current + previous Sippy windows)",
        "releases": {},
        "overall": {},
        "problem_jobs": [],
        "duration_estimates": {},
    }

    # Build a lookup for cluster profiles from inventory
    cluster_profiles = {}
    if inventory:
        for job in inventory:
            cluster_profiles[job.get("job_name", "")] = job.get("cluster_profile", "")

    all_jobs = []

    for release, jobs in sippy_data.get("jobs_by_release", {}).items():
        release_stats = {
            "total_jobs": len(jobs),
            "current_runs": 0,
            "current_passes": 0,
            "previous_runs": 0,
            "previous_passes": 0,
            "combined_runs": 0,
            "combined_passes": 0,
            "pass_rate_current": 0,
            "pass_rate_combined": 0,
            "trend": "",
        }

        for job in jobs:
            name = job.get("name", "")
            current_runs = job.get("current_runs", 0)
            current_passes = job.get("current_passes", 0)
            previous_runs = job.get("previous_runs", 0)
            previous_passes = job.get("previous_passes", 0)

            combined_runs = current_runs + previous_runs
            combined_passes = current_passes + previous_passes

            release_stats["current_runs"] += current_runs
            release_stats["current_passes"] += current_passes
            release_stats["previous_runs"] += previous_runs
            release_stats["previous_passes"] += previous_passes
            release_stats["combined_runs"] += combined_runs
            release_stats["combined_passes"] += combined_passes

            # Calculate pass rates
            current_rate = (current_passes / current_runs * 100) if current_runs > 0 else None
            previous_rate = (previous_passes / previous_runs * 100) if previous_runs > 0 else None
            combined_rate = (combined_passes / combined_runs * 100) if combined_runs > 0 else None

            # Determine trend
            trend = "stable"
            if current_rate is not None and previous_rate is not None:
                diff = current_rate - previous_rate
                if diff > 10:
                    trend = "improving"
                elif diff < -10:
                    trend = "degrading"

            # Get cluster profile for duration estimate
            cluster = cluster_profiles.get(name, "unknown")
            duration_est = DURATION_ESTIMATES.get(cluster, {"min": 60, "typical": 90, "max": 180})

            job_info = {
                "release": release,
                "name": name,
                "brief_name": job.get("brief_name", name),
                "cluster_profile": cluster,
                "current_runs": current_runs,
                "current_passes": current_passes,
                "current_pass_rate": current_rate,
                "previous_runs": previous_runs,
                "previous_passes": previous_passes,
                "previous_pass_rate": previous_rate,
                "combined_runs": combined_runs,
                "combined_passes": combined_passes,
                "combined_pass_rate": combined_rate,
                "trend": trend,
                "last_pass": job.get("last_pass", ""),
                "open_bugs": job.get("open_bugs", 0),
                "estimated_duration_min": duration_est["typical"],
            }
            all_jobs.append(job_info)

            # Track problem jobs (< 80% and has runs)
            if combined_rate is not None and combined_rate < 80 and combined_runs >= 2:
                results["problem_jobs"].append(job_info)

        # Calculate release-level rates
        if release_stats["current_runs"] > 0:
            release_stats["pass_rate_current"] = (
                release_stats["current_passes"] / release_stats["current_runs"] * 100
            )
        if release_stats["combined_runs"] > 0:
            release_stats["pass_rate_combined"] = (
                release_stats["combined_passes"] / release_stats["combined_runs"] * 100
            )

        # Determine release trend
        if release_stats["current_runs"] > 0 and release_stats["previous_runs"] > 0:
            curr_rate = release_stats["current_passes"] / release_stats["current_runs"]
            prev_rate = release_stats["previous_passes"] / release_stats["previous_runs"]
            diff = (curr_rate - prev_rate) * 100
            if diff > 5:
                release_stats["trend"] = "improving"
            elif diff < -5:
                release_stats["trend"] = "degrading"
            else:
                release_stats["trend"] = "stable"

        results["releases"][release] = release_stats

    # Overall statistics
    total_current_runs = sum(r["current_runs"] for r in results["releases"].values())
    total_current_passes = sum(r["current_passes"] for r in results["releases"].values())
    total_combined_runs = sum(r["combined_runs"] for r in results["releases"].values())
    total_combined_passes = sum(r["combined_passes"] for r in results["releases"].values())

    results["overall"] = {
        "total_jobs": len(all_jobs),
        "current_runs": total_current_runs,
        "current_passes": total_current_passes,
        "current_pass_rate": (total_current_passes / total_current_runs * 100) if total_current_runs > 0 else 0,
        "combined_runs": total_combined_runs,
        "combined_passes": total_combined_passes,
        "combined_pass_rate": (total_combined_passes / total_combined_runs * 100) if total_combined_runs > 0 else 0,
        "problem_job_count": len(results["problem_jobs"]),
    }

    # Sort problem jobs by pass rate
    results["problem_jobs"].sort(key=lambda x: x.get("combined_pass_rate", 0) or 0)

    # Duration estimates summary
    jobs_by_profile = {}
    for job in all_jobs:
        profile = job.get("cluster_profile", "unknown")
        if profile not in jobs_by_profile:
            jobs_by_profile[profile] = []
        jobs_by_profile[profile].append(job)

    for profile, jobs in jobs_by_profile.items():
        est = DURATION_ESTIMATES.get(profile, {"min": 60, "typical": 90, "max": 180})
        total_runs = sum(j["combined_runs"] for j in jobs)
        results["duration_estimates"][profile] = {
            "job_count": len(jobs),
            "total_runs": total_runs,
            "typical_duration_min": est["typical"],
            "estimated_total_hours": round(total_runs * est["typical"] / 60, 1),
        }

    return results, all_jobs


def generate_extended_report(results, all_jobs):
    """Generate markdown report with extended metrics."""
    report = []
    report.append("# OpenStack CI Extended Metrics Report")
    report.append("")
    report.append(f"**Generated:** {results['generated']}")
    report.append(f"**Period:** {results['period']}")
    report.append("")

    # Overall summary
    report.append("## Executive Summary")
    report.append("")
    overall = results["overall"]
    report.append(f"| Metric | Current (~7d) | Combined (~14d) |")
    report.append(f"|--------|---------------|-----------------|")
    report.append(f"| Total Jobs | {overall['total_jobs']} | {overall['total_jobs']} |")
    report.append(f"| Total Runs | {overall['current_runs']} | {overall['combined_runs']} |")
    report.append(f"| Pass Rate | {overall['current_pass_rate']:.1f}% | {overall['combined_pass_rate']:.1f}% |")
    report.append(f"| Problem Jobs (<80%) | - | {overall['problem_job_count']} |")
    report.append("")

    # Per-release breakdown
    report.append("## Metrics by Release")
    report.append("")
    report.append("| Release | Jobs | Runs (14d) | Pass Rate | Trend |")
    report.append("|---------|------|------------|-----------|-------|")
    for release in RELEASES:
        rel = results["releases"].get(release, {})
        trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(rel.get("trend", ""), "")
        report.append(
            f"| {release} | {rel.get('total_jobs', 0)} | "
            f"{rel.get('combined_runs', 0)} | "
            f"{rel.get('pass_rate_combined', 0):.1f}% | {trend_icon} {rel.get('trend', '')} |"
        )
    report.append("")

    # Problem jobs
    report.append("## Problem Jobs (Pass Rate < 80%)")
    report.append("")
    problem_jobs = results.get("problem_jobs", [])
    if problem_jobs:
        report.append(f"**{len(problem_jobs)} jobs** need attention:")
        report.append("")
        report.append("| Release | Job | Runs | Pass Rate | Trend | Bugs |")
        report.append("|---------|-----|------|-----------|-------|------|")
        for job in problem_jobs[:25]:
            trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(job.get("trend", ""), "")
            rate = job.get("combined_pass_rate")
            rate_str = f"{rate:.1f}%" if rate is not None else "N/A"
            report.append(
                f"| {job['release']} | {job['brief_name'][:50]} | "
                f"{job['combined_runs']} | {rate_str} | {trend_icon} | {job.get('open_bugs', 0)} |"
            )
        if len(problem_jobs) > 25:
            report.append(f"| ... | *{len(problem_jobs) - 25} more jobs* | | | | |")
    else:
        report.append("All jobs with sufficient runs have pass rate >= 80%.")
    report.append("")

    # Duration estimates
    report.append("## Estimated Job Durations by Cluster Profile")
    report.append("")
    report.append("*Note: Durations are estimates based on typical run times.*")
    report.append("")
    report.append("| Cluster Profile | Jobs | Runs (14d) | Typical Duration | Est. Total Hours |")
    report.append("|-----------------|------|------------|------------------|------------------|")
    for profile, est in sorted(results.get("duration_estimates", {}).items(),
                               key=lambda x: -x[1]["total_runs"]):
        report.append(
            f"| {profile} | {est['job_count']} | {est['total_runs']} | "
            f"~{est['typical_duration_min']}min | {est['estimated_total_hours']}h |"
        )
    report.append("")

    # Trend analysis
    report.append("## Trend Analysis")
    report.append("")
    improving = [j for j in all_jobs if j.get("trend") == "improving" and j["combined_runs"] >= 2]
    degrading = [j for j in all_jobs if j.get("trend") == "degrading" and j["combined_runs"] >= 2]
    report.append(f"- **Improving jobs:** {len(improving)}")
    report.append(f"- **Degrading jobs:** {len(degrading)}")
    report.append(f"- **Stable jobs:** {len(all_jobs) - len(improving) - len(degrading)}")
    report.append("")

    if degrading:
        report.append("### Degrading Jobs (investigate)")
        report.append("")
        for job in sorted(degrading, key=lambda x: (x.get("current_pass_rate") or 100))[:10]:
            curr = job.get("current_pass_rate")
            prev = job.get("previous_pass_rate")
            curr_str = f"{curr:.0f}%" if curr is not None else "N/A"
            prev_str = f"{prev:.0f}%" if prev is not None else "N/A"
            report.append(f"- **{job['brief_name'][:50]}** ({job['release']}): {prev_str} → {curr_str}")
        report.append("")

    report.append("---")
    report.append("")
    report.append("*Data Source: [Sippy](https://sippy.dptools.openshift.org/)*")
    report.append("")

    return "\n".join(report)


def main():
    global OUTPUT_DIR
    args = parse_args()
    OUTPUT_DIR = os.path.abspath(args.output_dir)

    print("=" * 60)
    print("OpenStack CI Extended Metrics")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Load existing data
    sippy_data = load_collected_data()
    if not sippy_data:
        print("Error: No Sippy data found. Run fetch_job_metrics.py first.")
        sys.exit(1)

    inventory = load_job_inventory()
    print(f"Loaded Sippy data from: {sippy_data.get('fetched_at')}")
    print(f"Job inventory loaded: {inventory is not None}")
    print()

    # Calculate extended metrics
    results, all_jobs = calculate_extended_metrics(sippy_data, inventory)

    # Save results
    results_path = os.path.join(OUTPUT_DIR, "extended_metrics.json")
    with open(results_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"Saved: {results_path}")

    all_jobs_path = os.path.join(OUTPUT_DIR, "extended_metrics_jobs.json")
    with open(all_jobs_path, 'w') as f:
        json.dump(all_jobs, f, indent=2)
    print(f"Saved: {all_jobs_path}")

    # Generate report
    report = generate_extended_report(results, all_jobs)
    report_path = os.path.join(OUTPUT_DIR, "extended_metrics_report.md")
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"Saved: {report_path}")

    # Summary
    print()
    print("=" * 60)
    print("Summary:")
    overall = results["overall"]
    print(f"  Total jobs: {overall['total_jobs']}")
    print(f"  Combined runs (14d): {overall['combined_runs']}")
    print(f"  Combined pass rate: {overall['combined_pass_rate']:.1f}%")
    print(f"  Problem jobs: {overall['problem_job_count']}")
    print("=" * 60)


if __name__ == "__main__":
    main()
