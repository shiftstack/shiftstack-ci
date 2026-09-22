#!/usr/bin/env python3
"""
Analyze platform comparison data and generate report.
Compares OpenStack CI pass rates against AWS, GCP, Azure, vSphere.
"""

import argparse
import json
import os
import sys
from datetime import datetime

RELEASES = ["4.17", "4.18", "4.19", "4.20", "4.21", "4.22"]
TARGET_PLATFORMS = ["OpenStack", "AWS", "GCP", "Azure", "vSphere", "Metal"]

# Will be set by parse_args()
OUTPUT_DIR = None


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Analyze platform comparison data and generate report"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for input/output files (default: script directory)"
    )
    return parser.parse_args()


def load_comparison_data():
    """Load platform comparison raw data."""
    filepath = os.path.join(OUTPUT_DIR, "platform_comparison_raw.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_extended_metrics():
    """Load extended metrics for OpenStack-specific data."""
    filepath = os.path.join(OUTPUT_DIR, "extended_metrics.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def analyze_platforms(data, openstack_metrics):
    """Analyze platform comparison data."""
    results = {
        "generated": datetime.now().isoformat(),
        "overall": {},
        "by_release": {},
        "openstack_position": {},
    }

    # Overall platform comparison
    overall = data.get("overall_by_platform", {})

    # Calculate OpenStack baseline
    openstack_rate = 0
    if "OpenStack" in overall:
        openstack_rate = overall["OpenStack"].get("pass_rate", 0)
    elif openstack_metrics:
        openstack_rate = openstack_metrics.get("overall", {}).get("combined_pass_rate", 0)

    # Build comparison table
    platforms = []
    for platform in TARGET_PLATFORMS:
        if platform in overall:
            pdata = overall[platform]
            rate = pdata.get("pass_rate", 0)
            delta = rate - openstack_rate if platform != "OpenStack" else 0
            platforms.append({
                "platform": platform,
                "job_count": pdata.get("job_count", 0),
                "total_runs": pdata.get("total_runs", 0),
                "total_passes": pdata.get("total_passes", 0),
                "pass_rate": rate,
                "vs_openstack": delta,
            })

    # Sort by pass rate descending
    platforms.sort(key=lambda x: -x["pass_rate"])
    results["overall"]["platforms"] = platforms

    # Find OpenStack position
    for i, p in enumerate(platforms):
        if p["platform"] == "OpenStack":
            results["openstack_position"]["rank"] = i + 1
            results["openstack_position"]["total"] = len(platforms)
            break

    # Per-release comparison
    for release in RELEASES:
        release_data = data.get("releases", {}).get(release, {})
        job_metrics = release_data.get("job_metrics", {})

        release_platforms = []
        for platform in TARGET_PLATFORMS:
            if platform in job_metrics:
                pdata = job_metrics[platform]
                release_platforms.append({
                    "platform": platform,
                    "job_count": pdata.get("job_count", 0),
                    "total_runs": pdata.get("total_runs", 0),
                    "pass_rate": pdata.get("pass_rate", 0),
                })

        release_platforms.sort(key=lambda x: -x["pass_rate"])
        results["by_release"][release] = release_platforms

    return results


def generate_report(analysis):
    """Generate markdown report for platform comparison."""
    report = []
    report.append("# Platform Comparison Report")
    report.append("")
    report.append(f"**Generated:** {analysis['generated']}")
    report.append("")
    report.append("This report compares OpenStack CI job pass rates against other cloud platforms.")
    report.append("")

    # Executive summary
    report.append("## Executive Summary")
    report.append("")

    platforms = analysis.get("overall", {}).get("platforms", [])
    pos = analysis.get("openstack_position", {})

    if pos:
        report.append(f"OpenStack ranks **#{pos.get('rank', '?')} of {pos.get('total', '?')}** platforms by pass rate.")
        report.append("")

    # Find best performer for comparison
    if platforms:
        best = platforms[0]
        openstack = next((p for p in platforms if p["platform"] == "OpenStack"), None)
        if openstack and best["platform"] != "OpenStack":
            gap = best["pass_rate"] - openstack["pass_rate"]
            report.append(f"- **Gap to best ({best['platform']}):** {gap:+.1f}%")
        if openstack:
            report.append(f"- **OpenStack pass rate:** {openstack['pass_rate']:.1f}%")
            report.append(f"- **OpenStack job volume:** {openstack['total_runs']:,} runs across {openstack['job_count']} jobs")
    report.append("")

    # Overall comparison table
    report.append("## Overall Platform Comparison")
    report.append("")
    report.append("| Rank | Platform | Jobs | Runs | Pass Rate | vs OpenStack |")
    report.append("|------|----------|------|------|-----------|--------------|")

    for i, p in enumerate(platforms, 1):
        delta = p.get("vs_openstack", 0)
        delta_str = f"+{delta:.1f}%" if delta > 0 else (f"{delta:.1f}%" if delta < 0 else "baseline")
        runs_str = f"{p['total_runs']:,}" if p['total_runs'] >= 1000 else str(p['total_runs'])
        report.append(
            f"| {i} | {p['platform']} | {p['job_count']} | {runs_str} | "
            f"{p['pass_rate']:.1f}% | {delta_str} |"
        )
    report.append("")

    # Key observations
    report.append("## Key Observations")
    report.append("")

    if platforms:
        openstack = next((p for p in platforms if p["platform"] == "OpenStack"), None)
        if openstack:
            # Calculate how many platforms are better
            better = [p for p in platforms if p["pass_rate"] > openstack["pass_rate"]]
            worse = [p for p in platforms if p["pass_rate"] < openstack["pass_rate"]]

            if better:
                report.append(f"### Platforms with Better Pass Rates ({len(better)})")
                report.append("")
                for p in better:
                    gap = p["pass_rate"] - openstack["pass_rate"]
                    report.append(f"- **{p['platform']}:** {p['pass_rate']:.1f}% (+{gap:.1f}% vs OpenStack)")
                report.append("")

            if worse:
                report.append(f"### Platforms with Lower Pass Rates ({len(worse)})")
                report.append("")
                for p in worse:
                    gap = openstack["pass_rate"] - p["pass_rate"]
                    report.append(f"- **{p['platform']}:** {p['pass_rate']:.1f}% (-{gap:.1f}% vs OpenStack)")
                report.append("")

    # Per-release breakdown
    report.append("## Pass Rate by Release")
    report.append("")
    report.append("| Release | " + " | ".join(TARGET_PLATFORMS) + " |")
    report.append("|---------|" + "|".join(["-------"] * len(TARGET_PLATFORMS)) + "|")

    for release in RELEASES:
        release_data = analysis.get("by_release", {}).get(release, [])
        rates = {}
        for p in release_data:
            rates[p["platform"]] = p["pass_rate"]

        row = f"| {release} |"
        for platform in TARGET_PLATFORMS:
            if platform in rates:
                row += f" {rates[platform]:.1f}% |"
            else:
                row += " - |"
        report.append(row)
    report.append("")

    # Analysis
    report.append("## Analysis")
    report.append("")
    report.append("### Potential Causes for Pass Rate Differences")
    report.append("")
    report.append("1. **Infrastructure maturity**: Platforms with longer CI history may have more stable infrastructure")
    report.append("2. **Test suite differences**: Each platform runs different test subsets")
    report.append("3. **Job volume**: Higher volume platforms may have more resources/attention")
    report.append("4. **Platform complexity**: Some platforms have inherent complexity differences")
    report.append("")

    report.append("### Recommendations")
    report.append("")
    report.append("1. Investigate top-performing platform configurations for applicable improvements")
    report.append("2. Compare test failure patterns across platforms")
    report.append("3. Review infrastructure provisioning reliability")
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
    print("OpenStack CI Platform Comparison Analysis")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Load data
    data = load_comparison_data()
    if not data:
        print("Error: No platform comparison data found.")
        print("Run fetch_comparison_data.py first.")
        sys.exit(1)

    openstack_metrics = load_extended_metrics()

    print(f"Loaded data from: {data.get('fetched_at')}")
    print()

    # Analyze
    analysis = analyze_platforms(data, openstack_metrics)

    # Save analysis
    analysis_path = os.path.join(OUTPUT_DIR, "platform_comparison_analysis.json")
    with open(analysis_path, 'w') as f:
        json.dump(analysis, f, indent=2)
    print(f"Saved: {analysis_path}")

    # Generate report
    report = generate_report(analysis)
    report_path = os.path.join(OUTPUT_DIR, "platform_comparison_report.md")
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"Saved: {report_path}")

    # Print summary
    print()
    print("=" * 60)
    print("Summary:")
    platforms = analysis.get("overall", {}).get("platforms", [])
    for i, p in enumerate(platforms, 1):
        marker = " <-- OpenStack" if p["platform"] == "OpenStack" else ""
        print(f"  {i}. {p['platform']}: {p['pass_rate']:.1f}%{marker}")
    print("=" * 60)


if __name__ == "__main__":
    main()
