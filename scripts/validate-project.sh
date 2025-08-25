#!/bin/bash

# Project Independence Validation Script
# Checks that the project has no external dependencies

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Project Independence Validation ==="
echo "Project root: $PROJECT_ROOT"
echo

# Check for hardcoded paths
echo "Checking for hardcoded external paths..."
HARDCODED_PATHS=$(grep -r "/home/itamarba" "$PROJECT_ROOT/scripts/" 2>/dev/null | grep -v "\.backup" || true)

if [[ -n "$HARDCODED_PATHS" ]]; then
    echo "❌ Found hardcoded external paths:"
    echo "$HARDCODED_PATHS"
    echo
else
    echo "✅ No hardcoded external paths found"
    echo
fi

# Check required directories
echo "Checking required directories..."
REQUIRED_DIRS=("secure" "logs" "cache" "temp")
for dir in "${REQUIRED_DIRS[@]}"; do
    if [[ -d "$PROJECT_ROOT/$dir" ]]; then
        echo "✅ $dir/ directory exists"
    else
        echo "❌ $dir/ directory missing"
    fi
done
echo

# Check required scripts
echo "Checking required scripts..."
REQUIRED_SCRIPTS=("build-vm-cache.sh" "securefile-v2.ps1" "vm-search-manager-v3.sh")
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ -f "$PROJECT_ROOT/scripts/$script" ]]; then
        echo "✅ $script exists"
    else
        echo "❌ $script missing"
    fi
done
echo

# Check script permissions
echo "Checking script permissions..."
for script in "$PROJECT_ROOT/scripts"/*.sh "$PROJECT_ROOT/scripts"/*.ps1; do
    if [[ -f "$script" ]]; then
        if [[ -x "$script" ]]; then
            echo "✅ $(basename "$script") is executable"
        else
            echo "❌ $(basename "$script") is not executable"
        fi
    fi
done
echo

echo "=== Validation Complete ==="
