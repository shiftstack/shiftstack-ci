#!/bin/bash
#
# Run all OpenStack CI analysis scripts in the correct order.
#
# Usage:
#   ./run_analysis.sh [--config-dir /path/to/ci-operator/config] [--output-dir /path/to/output]
#
# If --config-dir is not specified, defaults to ../../../ci-operator/config
# (relative to script location, assuming standard repo layout)
#
# If --output-dir is not specified, outputs to current working directory
# This allows running from any location in the filesystem

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default config directory (relative to script location)
CONFIG_DIR="${SCRIPT_DIR}/../../../ci-operator/config"

# Default output directory is current working directory
OUTPUT_DIR="$(pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config-dir)
            CONFIG_DIR="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE="--force"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --config-dir DIR   Path to ci-operator/config directory"
            echo "  --output-dir DIR   Directory for output files (default: current directory)"
            echo "  --force            Refetch data from Sippy API"
            echo ""
            echo "Examples:"
            echo "  # Run from repo root, output to current directory"
            echo "  ./hack/openstack-ci-analysis/reporting-toolkit/run_analysis.sh"
            echo ""
            echo "  # Run from anywhere, specify both directories"
            echo "  ./run_analysis.sh --config-dir /path/to/release/ci-operator/config --output-dir /tmp/analysis"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Resolve to absolute paths
CONFIG_DIR="$(cd "$CONFIG_DIR" 2>/dev/null && pwd)" || {
    echo "Error: Config directory not found: $CONFIG_DIR"
    echo "Use --config-dir to specify the path to ci-operator/config"
    exit 1
}

OUTPUT_DIR="$(mkdir -p "$OUTPUT_DIR" && cd "$OUTPUT_DIR" && pwd)"

echo "============================================================"
echo "OpenStack CI Analysis Toolkit"
echo "============================================================"
echo "Script directory: $SCRIPT_DIR"
echo "Config directory: $CONFIG_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "============================================================"
echo ""

# Phase 1: Data Collection
echo "=== Phase 1: Data Collection ==="
echo ""

echo "[1/4] Extracting job inventory..."
python3 "$SCRIPT_DIR/extract_openstack_jobs.py" \
    --config-dir "$CONFIG_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --summary

echo ""
echo "[2/4] Fetching job metrics from Sippy..."
python3 "$SCRIPT_DIR/fetch_job_metrics.py" \
    --output-dir "$OUTPUT_DIR" \
    ${FORCE:+"$FORCE"}

echo ""
echo "[3/4] Calculating extended metrics..."
python3 "$SCRIPT_DIR/fetch_extended_metrics.py" \
    --output-dir "$OUTPUT_DIR"

echo ""
echo "[4/4] Fetching platform comparison data..."
python3 "$SCRIPT_DIR/fetch_comparison_data.py" \
    --output-dir "$OUTPUT_DIR"

# Phase 2: Configuration Analysis
echo ""
echo "=== Phase 2: Configuration Analysis ==="
echo ""

echo "[1/3] Analyzing redundancy..."
python3 "$SCRIPT_DIR/analyze_redundancy.py" \
    --output-dir "$OUTPUT_DIR"

echo ""
echo "[2/3] Analyzing coverage gaps..."
python3 "$SCRIPT_DIR/analyze_coverage.py" \
    --output-dir "$OUTPUT_DIR"

echo ""
echo "[3/3] Analyzing trigger patterns..."
python3 "$SCRIPT_DIR/analyze_triggers.py" \
    --output-dir "$OUTPUT_DIR"

# Phase 3: Runtime Analysis
echo ""
echo "=== Phase 3: Runtime Analysis ==="
echo ""

echo "[1/3] Analyzing platform comparison..."
python3 "$SCRIPT_DIR/analyze_platform_comparison.py" \
    --output-dir "$OUTPUT_DIR"

echo ""
echo "[2/3] Analyzing workflow pass rates..."
python3 "$SCRIPT_DIR/analyze_workflow_passrate.py" \
    --output-dir "$OUTPUT_DIR"

echo ""
echo "[3/3] Categorizing failures..."
python3 "$SCRIPT_DIR/categorize_failures.py" \
    --output-dir "$OUTPUT_DIR"

# Summary
echo ""
echo "============================================================"
echo "Analysis Complete!"
echo "============================================================"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Generated Reports:"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | while read -r f; do
    echo "  - $(basename "$f")"
done
echo ""
echo "Data Files:"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.json" -type f 2>/dev/null | wc -l | xargs -I {} echo "  {} JSON files generated"
echo ""
echo "To view key findings, run:"
echo "  cd $OUTPUT_DIR"
echo "  python3 -c \"import json; d=json.load(open('extended_metrics.json')); print(f'Pass rate: {d[\\\"overall\\\"][\\\"combined_pass_rate\\\"]:.1f}%')\""
echo ""
