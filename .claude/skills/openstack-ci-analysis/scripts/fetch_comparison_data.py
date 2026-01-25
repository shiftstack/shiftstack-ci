#!/usr/bin/env python3
"""
Fetch platform comparison data from Sippy API.
Fetches variant data for all platforms to compare OpenStack against AWS, GCP, Azure, vSphere.
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

# Platform variants to compare
PLATFORMS = ["OpenStack", "AWS", "GCP", "Azure", "vSphere", "Metal"]


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Fetch platform comparison data from Sippy API"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for output files (default: script directory)"
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


def fetch_variants_for_release(release):
    """Fetch variant data for a specific release."""
    url = f"{SIPPY_BASE}/variants?release={release}"
    print(f"Fetching variants for release {release}...")

    data = fetch_json(url)
    if data is None:
        print(f"  Failed to fetch variants for {release}")
        return []

    print(f"  Retrieved {len(data)} variants")
    return data


def extract_platform_variants(variants):
    """Extract Platform:* variants from variant data."""
    platform_data = {}

    for variant in variants:
        name = variant.get("name", "")
        if name.startswith("Platform:"):
            platform = name.replace("Platform:", "")
            platform_data[platform] = {
                "name": platform,
                "variant_full_name": name,
                "current_pass_percentage": variant.get("current_pass_percentage", 0),
                "current_runs": variant.get("current_runs", 0),
                "current_passes": variant.get("current_passes", 0),
                "previous_pass_percentage": variant.get("previous_pass_percentage", 0),
                "previous_runs": variant.get("previous_runs", 0),
                "previous_passes": variant.get("previous_passes", 0),
                "job_count": variant.get("job_count", 0),
            }

    return platform_data


def fetch_jobs_for_release(release):
    """Fetch all jobs for a release to get platform job counts."""
    url = f"{SIPPY_BASE}/jobs?release={release}"
    print(f"  Fetching jobs for platform counts...")

    data = fetch_json(url)
    if data is None:
        return {}

    # Count jobs by platform
    platform_counts = {}
    platform_runs = {}
    platform_passes = {}

    for job in data:
        name = job.get("name", "").lower()
        runs = job.get("current_runs", 0) + job.get("previous_runs", 0)
        passes = job.get("current_passes", 0) + job.get("previous_passes", 0)

        # Determine platform from job name
        platform = None
        if "openstack" in name:
            platform = "OpenStack"
        elif "aws" in name:
            platform = "AWS"
        elif "gcp" in name:
            platform = "GCP"
        elif "azure" in name:
            platform = "Azure"
        elif "vsphere" in name:
            platform = "vSphere"
        elif "metal" in name or "baremetal" in name:
            platform = "Metal"

        if platform:
            platform_counts[platform] = platform_counts.get(platform, 0) + 1
            platform_runs[platform] = platform_runs.get(platform, 0) + runs
            platform_passes[platform] = platform_passes.get(platform, 0) + passes

    result = {}
    for platform in platform_counts:
        runs = platform_runs.get(platform, 0)
        passes = platform_passes.get(platform, 0)
        result[platform] = {
            "job_count": platform_counts[platform],
            "total_runs": runs,
            "total_passes": passes,
            "pass_rate": (passes / runs * 100) if runs > 0 else 0,
        }

    return result


def main():
    global OUTPUT_DIR
    args = parse_args()
    OUTPUT_DIR = os.path.abspath(args.output_dir)

    # Create output directory if needed
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 60)
    print("OpenStack CI Platform Comparison Data Fetcher")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    results = {
        "fetched_at": datetime.now().isoformat(),
        "releases": {},
        "overall_by_platform": {},
    }

    # Fetch data for each release
    for release in RELEASES:
        print(f"\n--- Release {release} ---")

        # Fetch variants
        variants = fetch_variants_for_release(release)
        platform_variants = extract_platform_variants(variants) if variants else {}

        # Fetch job counts
        platform_jobs = fetch_jobs_for_release(release)

        # Combine data
        release_data = {
            "variants": platform_variants,
            "job_metrics": platform_jobs,
        }
        results["releases"][release] = release_data

        time.sleep(1)  # Be nice to the API

    # Calculate overall metrics by platform
    overall = {}
    for release, data in results["releases"].items():
        for platform, metrics in data.get("job_metrics", {}).items():
            if platform not in overall:
                overall[platform] = {
                    "job_count": 0,
                    "total_runs": 0,
                    "total_passes": 0,
                }
            overall[platform]["job_count"] += metrics.get("job_count", 0)
            overall[platform]["total_runs"] += metrics.get("total_runs", 0)
            overall[platform]["total_passes"] += metrics.get("total_passes", 0)

    # Calculate pass rates
    for platform, data in overall.items():
        runs = data["total_runs"]
        passes = data["total_passes"]
        data["pass_rate"] = (passes / runs * 100) if runs > 0 else 0

    results["overall_by_platform"] = overall

    # Save results
    output_path = os.path.join(OUTPUT_DIR, "platform_comparison_raw.json")
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"\nSaved: {output_path}")

    # Print summary
    print("\n" + "=" * 60)
    print("Summary by Platform (all releases):")
    print("-" * 60)
    print(f"{'Platform':<15} {'Jobs':>8} {'Runs':>10} {'Pass Rate':>10}")
    print("-" * 60)
    for platform in sorted(overall.keys(), key=lambda x: -overall[x]["pass_rate"]):
        data = overall[platform]
        print(f"{platform:<15} {data['job_count']:>8} {data['total_runs']:>10} {data['pass_rate']:>9.1f}%")
    print("=" * 60)


if __name__ == "__main__":
    main()
