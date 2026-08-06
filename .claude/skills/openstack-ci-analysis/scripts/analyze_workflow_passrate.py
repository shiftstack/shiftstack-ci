#!/usr/bin/env python3
"""
Analyze workflow pass rates by correlating job inventory with Sippy metrics.
Maps inventory job names to Sippy data using substring matching.
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
        description="Analyze workflow pass rates"
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.dirname(os.path.abspath(__file__)),
        help="Directory for input/output files (default: script directory)"
    )
    return parser.parse_args()


def load_job_inventory():
    """Load job inventory."""
    filepath = os.path.join(OUTPUT_DIR, "openstack_jobs_inventory.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_sippy_data():
    """Load Sippy job data."""
    filepath = os.path.join(OUTPUT_DIR, "sippy_jobs_raw.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def load_extended_metrics_jobs():
    """Load extended metrics per job."""
    filepath = os.path.join(OUTPUT_DIR, "extended_metrics_jobs.json")
    if os.path.exists(filepath):
        with open(filepath) as f:
            return json.load(f)
    return None


def extract_workflow_from_name(job_name):
    """Extract workflow pattern from job name."""
    # Common workflow patterns in OpenStack job names
    patterns = [
        "openshift-e2e-openstack-ipi",
        "openshift-e2e-openstack-upi",
        "openshift-upgrade-openstack",
        "openshift-e2e-openstack",
        "openshift-installer-openstack",
    ]

    # Check for specific test scenarios in name
    name_lower = job_name.lower()

    # Extract key test characteristics
    characteristics = []
    if "serial" in name_lower:
        characteristics.append("serial")
    if "parallel" in name_lower:
        characteristics.append("parallel")
    if "fips" in name_lower:
        characteristics.append("fips")
    if "proxy" in name_lower:
        characteristics.append("proxy")
    if "dualstack" in name_lower:
        characteristics.append("dualstack")
    if "singlestackv6" in name_lower or "single-stack-v6" in name_lower:
        characteristics.append("singlestackv6")
    if "upgrade" in name_lower:
        characteristics.append("upgrade")
    if "nfv" in name_lower:
        characteristics.append("nfv")
    if "hwoffload" in name_lower:
        characteristics.append("hwoffload")
    if "ccpmso" in name_lower:
        characteristics.append("ccpmso")
    if "csi" in name_lower:
        characteristics.append("csi")
    if "manila" in name_lower:
        characteristics.append("manila")
    if "cinder" in name_lower:
        characteristics.append("cinder")
    if "externallb" in name_lower:
        characteristics.append("externallb")
    if "kuryr" in name_lower:
        characteristics.append("kuryr")
    if "hypershift" in name_lower:
        characteristics.append("hypershift")
    if "techpreview" in name_lower:
        characteristics.append("techpreview")
    if "etcd" in name_lower:
        characteristics.append("etcd")

    if characteristics:
        return "-".join(sorted(characteristics))
    return "e2e-default"


def correlate_jobs(inventory, sippy_data, extended_jobs):
    """Correlate inventory jobs with Sippy data."""
    # Build Sippy job lookup by name
    sippy_lookup = {}
    for release, jobs in sippy_data.get("jobs_by_release", {}).items():
        for job in jobs:
            name = job.get("name", "")
            sippy_lookup[name] = {
                "release": release,
                "current_runs": job.get("current_runs", 0),
                "current_passes": job.get("current_passes", 0),
                "previous_runs": job.get("previous_runs", 0),
                "previous_passes": job.get("previous_passes", 0),
                "pass_rate": job.get("current_pass_percentage", 0),
            }

    # Build extended metrics lookup
    extended_lookup = {}
    if extended_jobs:
        for job in extended_jobs:
            name = job.get("name", "")
            extended_lookup[name] = job

    # Group inventory jobs by workflow
    workflow_jobs = defaultdict(list)

    for inv_job in inventory:
        job_name = inv_job.get("job_name", "")
        workflow = inv_job.get("workflow", "") or extract_workflow_from_name(job_name)
        job_type = inv_job.get("job_type", "")

        # Only analyze periodic jobs (which have Sippy data)
        if job_type != "periodic":
            continue

        # Try to find matching Sippy job
        sippy_match = None
        extended_match = None

        # Look for exact or partial match
        for sippy_name, sippy_job in sippy_lookup.items():
            # Check if inventory job name is in Sippy job name or vice versa
            if job_name in sippy_name or sippy_name.endswith(job_name):
                sippy_match = sippy_job
                extended_match = extended_lookup.get(sippy_name)
                break

        job_info = {
            "job_name": job_name,
            "workflow": workflow,
            "cluster_profile": inv_job.get("cluster_profile", ""),
            "org": inv_job.get("org", ""),
            "repo": inv_job.get("repo", ""),
            "branch": inv_job.get("branch", ""),
            "has_sippy_data": sippy_match is not None,
        }

        if sippy_match:
            job_info.update({
                "release": sippy_match.get("release", ""),
                "current_runs": sippy_match.get("current_runs", 0),
                "current_passes": sippy_match.get("current_passes", 0),
                "previous_runs": sippy_match.get("previous_runs", 0),
                "previous_passes": sippy_match.get("previous_passes", 0),
                "pass_rate": sippy_match.get("pass_rate", 0),
            })
        if extended_match:
            job_info["combined_runs"] = extended_match.get("combined_runs", 0)
            job_info["combined_pass_rate"] = extended_match.get("combined_pass_rate", 0)
            job_info["trend"] = extended_match.get("trend", "")

        # Extract scenario from job name
        scenario = extract_workflow_from_name(job_name)
        workflow_jobs[scenario].append(job_info)

    return workflow_jobs


def analyze_workflows(workflow_jobs):
    """Analyze pass rates by workflow."""
    results = {
        "generated": datetime.now().isoformat(),
        "workflows": [],
        "summary": {},
    }

    workflow_stats = []

    for workflow, jobs in workflow_jobs.items():
        jobs_with_data = [j for j in jobs if j.get("has_sippy_data")]

        if not jobs_with_data:
            continue

        total_runs = sum(j.get("current_runs", 0) + j.get("previous_runs", 0) for j in jobs_with_data)
        total_passes = sum(j.get("current_passes", 0) + j.get("previous_passes", 0) for j in jobs_with_data)
        pass_rate = (total_passes / total_runs * 100) if total_runs > 0 else 0

        # Count problem jobs
        problem_jobs = [j for j in jobs_with_data if j.get("pass_rate", 100) < 80]

        # Calculate trend
        improving = sum(1 for j in jobs_with_data if j.get("trend") == "improving")
        degrading = sum(1 for j in jobs_with_data if j.get("trend") == "degrading")

        trend = "stable"
        if improving > degrading and improving > 0:
            trend = "improving"
        elif degrading > improving and degrading > 0:
            trend = "degrading"

        # Determine severity
        severity = "ok"
        if pass_rate < 50:
            severity = "critical"
        elif pass_rate < 70:
            severity = "warning"
        elif pass_rate < 80:
            severity = "needs_attention"

        workflow_stats.append({
            "workflow": workflow,
            "job_count": len(jobs_with_data),
            "total_runs": total_runs,
            "total_passes": total_passes,
            "pass_rate": pass_rate,
            "problem_job_count": len(problem_jobs),
            "trend": trend,
            "severity": severity,
            "jobs": jobs_with_data,
        })

    # Sort by pass rate (lowest first = most problematic)
    workflow_stats.sort(key=lambda x: x["pass_rate"])

    results["workflows"] = workflow_stats

    # Summary
    total_workflows = len(workflow_stats)
    critical = sum(1 for w in workflow_stats if w["severity"] == "critical")
    warning = sum(1 for w in workflow_stats if w["severity"] == "warning")

    results["summary"] = {
        "total_workflows_analyzed": total_workflows,
        "critical_workflows": critical,
        "warning_workflows": warning,
        "ok_workflows": total_workflows - critical - warning,
    }

    return results


def generate_report(analysis):
    """Generate markdown report for workflow analysis."""
    report = []
    report.append("# Workflow Pass Rate Analysis")
    report.append("")
    report.append(f"**Generated:** {analysis['generated']}")
    report.append("")
    report.append("This report analyzes pass rates grouped by test workflow/scenario type.")
    report.append("")

    # Summary
    summary = analysis.get("summary", {})
    report.append("## Summary")
    report.append("")
    report.append(f"| Metric | Count |")
    report.append(f"|--------|-------|")
    report.append(f"| Total Workflows Analyzed | {summary.get('total_workflows_analyzed', 0)} |")
    report.append(f"| Critical (<50% pass rate) | {summary.get('critical_workflows', 0)} |")
    report.append(f"| Warning (50-70% pass rate) | {summary.get('warning_workflows', 0)} |")
    report.append(f"| OK (>70% pass rate) | {summary.get('ok_workflows', 0)} |")
    report.append("")

    workflows = analysis.get("workflows", [])

    # Critical workflows
    critical = [w for w in workflows if w["severity"] == "critical"]
    if critical:
        report.append("## Critical Workflows (Pass Rate < 50%)")
        report.append("")
        report.append("These workflows require immediate attention:")
        report.append("")
        report.append("| Workflow | Jobs | Runs | Pass Rate | Trend |")
        report.append("|----------|------|------|-----------|-------|")
        for w in critical:
            trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(w["trend"], "")
            report.append(
                f"| {w['workflow']} | {w['job_count']} | {w['total_runs']} | "
                f"**{w['pass_rate']:.1f}%** | {trend_icon} |"
            )
        report.append("")

    # Warning workflows
    warning = [w for w in workflows if w["severity"] == "warning"]
    if warning:
        report.append("## Warning Workflows (Pass Rate 50-70%)")
        report.append("")
        report.append("| Workflow | Jobs | Runs | Pass Rate | Trend |")
        report.append("|----------|------|------|-----------|-------|")
        for w in warning:
            trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(w["trend"], "")
            report.append(
                f"| {w['workflow']} | {w['job_count']} | {w['total_runs']} | "
                f"{w['pass_rate']:.1f}% | {trend_icon} |"
            )
        report.append("")

    # All workflows table
    report.append("## All Workflows by Pass Rate")
    report.append("")
    report.append("| Rank | Workflow | Jobs | Runs | Pass Rate | Problems | Trend |")
    report.append("|------|----------|------|------|-----------|----------|-------|")
    for i, w in enumerate(workflows, 1):
        trend_icon = {"improving": "↑", "degrading": "↓", "stable": "→"}.get(w["trend"], "")
        severity_marker = ""
        if w["severity"] == "critical":
            severity_marker = " ⚠️"
        elif w["severity"] == "warning":
            severity_marker = " ⚡"
        report.append(
            f"| {i} | {w['workflow']}{severity_marker} | {w['job_count']} | "
            f"{w['total_runs']} | {w['pass_rate']:.1f}% | {w['problem_job_count']} | {trend_icon} |"
        )
    report.append("")

    # Recommendations
    report.append("## Recommendations")
    report.append("")
    if critical:
        report.append("### Immediate Actions")
        report.append("")
        for w in critical[:5]:
            report.append(f"- **{w['workflow']}**: {w['pass_rate']:.1f}% pass rate with {w['total_runs']} runs - investigate root cause")
        report.append("")

    if warning:
        report.append("### Short-term Improvements")
        report.append("")
        for w in warning[:5]:
            report.append(f"- **{w['workflow']}**: {w['pass_rate']:.1f}% pass rate - monitor and triage failures")
        report.append("")

    report.append("---")
    report.append("")
    report.append("*Data Sources: Job inventory + [Sippy](https://sippy.dptools.openshift.org/)*")
    report.append("")

    return "\n".join(report)


def main():
    global OUTPUT_DIR
    args = parse_args()
    OUTPUT_DIR = os.path.abspath(args.output_dir)

    print("=" * 60)
    print("OpenStack CI Workflow Pass Rate Analysis")
    print("=" * 60)
    print(f"Output directory: {OUTPUT_DIR}")
    print()

    # Load data
    inventory = load_job_inventory()
    if not inventory:
        print("Error: No job inventory found. Run extract_openstack_jobs.py first.")
        sys.exit(1)
    print(f"Loaded inventory: {len(inventory)} jobs")

    sippy_data = load_sippy_data()
    if not sippy_data:
        print("Error: No Sippy data found. Run fetch_job_metrics.py first.")
        sys.exit(1)
    print(f"Loaded Sippy data from: {sippy_data.get('fetched_at')}")

    extended_jobs = load_extended_metrics_jobs()
    print(f"Extended metrics loaded: {extended_jobs is not None}")
    print()

    # Correlate and analyze
    workflow_jobs = correlate_jobs(inventory, sippy_data, extended_jobs)
    print(f"Found {len(workflow_jobs)} workflow types")

    analysis = analyze_workflows(workflow_jobs)

    # Save results
    analysis_path = os.path.join(OUTPUT_DIR, "workflow_passrate_analysis.json")
    with open(analysis_path, 'w') as f:
        # Remove job details for smaller output
        save_analysis = dict(analysis)
        save_analysis["workflows"] = [
            {k: v for k, v in w.items() if k != "jobs"}
            for w in analysis["workflows"]
        ]
        json.dump(save_analysis, f, indent=2)
    print(f"Saved: {analysis_path}")

    # Generate report
    report = generate_report(analysis)
    report_path = os.path.join(OUTPUT_DIR, "workflow_passrate_report.md")
    with open(report_path, 'w') as f:
        f.write(report)
    print(f"Saved: {report_path}")

    # Print summary
    print()
    print("=" * 60)
    print("Summary:")
    summary = analysis.get("summary", {})
    print(f"  Workflows analyzed: {summary.get('total_workflows_analyzed', 0)}")
    print(f"  Critical (<50%): {summary.get('critical_workflows', 0)}")
    print(f"  Warning (50-70%): {summary.get('warning_workflows', 0)}")
    print(f"  OK (>70%): {summary.get('ok_workflows', 0)}")
    print("=" * 60)


if __name__ == "__main__":
    main()
