---
name: openstack-ci-analysis
description: Analyzes OpenStack CI job health, pass rates, coverage gaps, and failure categories. Use when asked to analyze CI jobs, generate CI health reports, compare platform performance, or investigate job failures for OpenStack/ShiftStack.
---

# OpenStack CI Analysis

Comprehensive analysis of OpenStack CI job health using Sippy API metrics and CI configuration data.

## Prerequisites

- Python 3.6+ with pyyaml: `pip install pyyaml`
- Access to openshift/release repository (for `ci-operator/config`)

## Quick Start

Run all analysis with the wrapper script:

```bash
python3 scripts/run_analysis.sh \
    --config-dir /path/to/release/ci-operator/config \
    --output-dir /tmp/analysis
```

Add `--force` to refresh cached Sippy data.

## Workflow

### Phase 1: Data Collection

Run in order (each depends on prior outputs):

```bash
# 1. Extract job inventory from CI config YAML files
python3 scripts/extract_openstack_jobs.py \
    --config-dir $CONFIG_DIR \
    --output-dir $OUTPUT_DIR \
    --summary

# 2. Fetch pass rates from Sippy API
python3 scripts/fetch_job_metrics.py --output-dir $OUTPUT_DIR

# 3. Calculate 14-day combined metrics
python3 scripts/fetch_extended_metrics.py --output-dir $OUTPUT_DIR

# 4. Fetch platform comparison data
python3 scripts/fetch_comparison_data.py --output-dir $OUTPUT_DIR
```

### Phase 2: Configuration Analysis

These analyze the job inventory (can run in parallel):

```bash
python3 scripts/analyze_redundancy.py --output-dir $OUTPUT_DIR
python3 scripts/analyze_coverage.py --output-dir $OUTPUT_DIR
python3 scripts/analyze_triggers.py --output-dir $OUTPUT_DIR
```

### Phase 3: Runtime Analysis

These analyze Sippy metrics (can run in parallel):

```bash
python3 scripts/analyze_platform_comparison.py --output-dir $OUTPUT_DIR
python3 scripts/analyze_workflow_passrate.py --output-dir $OUTPUT_DIR
python3 scripts/categorize_failures.py --output-dir $OUTPUT_DIR
```

## Scripts Reference

| Script | Purpose | Requires |
|--------|---------|----------|
| `extract_openstack_jobs.py` | Extract jobs from ci-operator/config | config-dir |
| `fetch_job_metrics.py` | Fetch Sippy API metrics | - |
| `fetch_extended_metrics.py` | 14-day combined metrics | sippy_jobs_raw.json |
| `fetch_comparison_data.py` | Platform comparison data | - |
| `analyze_redundancy.py` | Find duplicate/overlapping jobs | inventory.json |
| `analyze_coverage.py` | Find coverage gaps across releases | inventory.json |
| `analyze_triggers.py` | Trigger optimization opportunities | inventory.json |
| `analyze_platform_comparison.py` | OpenStack vs AWS/GCP/Azure | platform_comparison_raw.json |
| `analyze_workflow_passrate.py` | Pass rates by workflow type | inventory.json, sippy_jobs_raw.json |
| `categorize_failures.py` | Classify failures by root cause | extended_metrics_jobs.json |

## Output Files

### Reports (Markdown)

| File | Contents |
|------|----------|
| `extended_metrics_report.md` | Overall health, trends, problem jobs |
| `platform_comparison_report.md` | OpenStack vs other platforms |
| `workflow_passrate_report.md` | Pass rates by workflow |
| `failure_categories_report.md` | Failures by root cause |
| `coverage_gaps_report.md` | Missing test coverage |
| `trigger_optimization_report.md` | Trigger improvements |
| `redundant_jobs_report.md` | Consolidation opportunities |

### Data (JSON)

| File | Contents |
|------|----------|
| `openstack_jobs_inventory.json` | Complete job inventory |
| `sippy_jobs_raw.json` | Cached Sippy data |
| `extended_metrics.json` | Combined metrics |
| `platform_comparison_analysis.json` | Platform analysis |
| `failure_categories.json` | Categorized failures |

## Generating Executive Summary

After running all scripts, extract key metrics:

```python
import json
import os

d = os.environ.get('OUTPUT_DIR', '.')

ext = json.load(open(f'{d}/extended_metrics.json'))
plat = json.load(open(f'{d}/platform_comparison_analysis.json'))
fail = json.load(open(f'{d}/failure_categories.json'))

print(f"Pass rate: {ext['overall']['combined_pass_rate']:.1f}%")
print(f"Problem jobs: {ext['overall']['problem_job_count']}")
print(f"OpenStack rank: #{plat['openstack_position']['rank']}/{plat['openstack_position']['total']}")

print("\nFailure Categories:")
for cat, count in fail['summary']['by_category'].items():
    pct = fail['summary']['percentages'][cat]
    print(f"  {cat}: {count} ({pct}%)")
```

## Cluster Profiles Analyzed

- openstack-vexxhost
- openstack-vh-mecha-central
- openstack-vh-mecha-az0
- openstack-vh-bm-rhos
- openstack-hwoffload
- openstack-nfv

## Failure Categories

| Category | Criteria |
|----------|----------|
| Infrastructure | Low pass rate on install/provision jobs |
| Flaky | 30-70% pass rate (inconsistent) |
| Product Bug | Low pass rate with bugs filed |
| Needs Triage | Unknown cause, requires investigation |

## Troubleshooting

| Error | Solution |
|-------|----------|
| "No Sippy data found" | Run `fetch_job_metrics.py` first |
| "No job inventory found" | Run `extract_openstack_jobs.py` first |
| Import error for yaml | `pip install pyyaml` |
| Config directory not found | Point to ci-operator/config in openshift/release repo |
