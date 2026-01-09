#!/usr/bin/env bash

# Suitey BATS Framework Module
# Handles BATS framework for Bash language
# Provides framework-specific test discovery, execution, and parsing for BATS projects
#
# This module works in conjunction with the Bash language module:
# - Language module (mod/languages/bash/mod.sh) detects Bash language presence
# - Framework module (this module) handles BATS-specific operations
# - Framework module has higher priority than language module for framework-specific operations

# Detect if BATS project is present (framework-level detection)
# Usage: detect <project_root>
# Returns: Detection result as flat data
# Behavior: Checks for .bats files (framework-specific indicator)
detect() {
    local project_root="$1"

    # Validate input
    if [[ -z "$project_root" ]] || [[ ! -d "$project_root" ]]; then
        echo "detected=false"
        echo "confidence=low"
        echo "indicators_count=0"
        echo "language=bash"
        echo "frameworks_0=bats"
        return 0
    fi

    # Check for .bats files (primary BATS indicator)
    # Look in common test directories: tests/bats/, test/bats/, tests/, test/
    local bats_files
    bats_files=$(find "$project_root" -maxdepth 3 -name "*.bats" -type f 2>/dev/null | head -1)
    if [[ -n "$bats_files" ]]; then
        echo "detected=true"
        echo "confidence=high"
        echo "indicators_0=bats_test_files"
        echo "indicators_count=1"
        echo "language=bash"
        echo "frameworks_0=bats"
        return 0
    fi

    # Check for BATS test directory structure (secondary indicator)
    if [[ -d "$project_root/tests/bats" ]] || [[ -d "$project_root/test/bats" ]]; then
        echo "detected=true"
        echo "confidence=medium"
        echo "indicators_0=bats_test_directory"
        echo "indicators_count=1"
        echo "language=bash"
        echo "frameworks_0=bats"
        return 0
    fi

    # Not detected
    echo "detected=false"
    echo "confidence=low"
    echo "indicators_count=0"
    echo "language=bash"
    echo "frameworks_0=bats"
    return 0
}

# Check if required binaries are available
# Usage: check_binaries <project_root>
# Returns: Binary status as flat data
# Behavior: Checks for bats binary in PATH and reports version if available
check_binaries() {
    local project_root="$1"

    # Check for bats binary in PATH
    if command -v bats >/dev/null 2>&1; then
        local bats_version
        bats_version=$(bats --version 2>/dev/null | head -1 || echo "unknown")
        # Remove "bats " prefix if present
        bats_version="${bats_version#bats }"
        echo "available=true"
        echo "binaries_0=bats"
        echo "binaries_count=1"
        echo "versions_bats=$bats_version"
        echo "container_check=false"
    else
        echo "available=false"
        echo "binaries_0=bats"
        echo "binaries_count=1"
        echo "container_check=false"
    fi

    return 0
}

# Discover test suites in the project using BATS-specific patterns
# Usage: discover_test_suites <project_root> <framework_metadata>
# Returns: Test suites as flat data
# Behavior: Finds .bats files in common test directories (tests/bats/, test/bats/, etc.)
discover_test_suites() {
    local project_root="$1"
    local framework_metadata="$2"

    # Validate input
    if [[ -z "$project_root" ]] || [[ ! -d "$project_root" ]]; then
        echo "suites_count=0"
        return 0
    fi

    local suites_count=0
    local suite_index=0
    local results=""

    # Discover .bats files in common test directories
    # BATS tests are typically organized in tests/bats/ or test/bats/ directories
    local test_dirs=("$project_root/tests/bats" "$project_root/test/bats" "$project_root/tests" "$project_root/test")
    
    for test_dir in "${test_dirs[@]}"; do
        if [[ -d "$test_dir" ]]; then
            local bats_files
            bats_files=$(find "$test_dir" -name "*.bats" -type f 2>/dev/null)
            
            if [[ -n "$bats_files" ]]; then
                local file_count
                file_count=$(echo "$bats_files" | wc -l)
                
                if [[ $file_count -gt 0 ]]; then
                    # Create a suite for this directory
                    local suite_name
                    suite_name=$(basename "$test_dir")
                    
                    if [[ -z "$results" ]]; then
                        results="suites_${suite_index}_name=${suite_name}"
                    else
                        results="${results}"$'\n'"suites_${suite_index}_name=${suite_name}"
                    fi
                    results="${results}"$'\n'"suites_${suite_index}_framework=bats"
                    results="${results}"$'\n'"suites_${suite_index}_test_files_count=${file_count}"
                    
                    suites_count=$((suites_count + 1))
                    suite_index=$((suite_index + 1))
                    
                    # Only process first matching directory to avoid duplicates
                    break
                fi
            fi
        fi
    done

    # If no test directories found, search for .bats files anywhere
    if [[ $suites_count -eq 0 ]]; then
        local bats_files
        bats_files=$(find "$project_root" -maxdepth 3 -name "*.bats" -type f 2>/dev/null)
        
        if [[ -n "$bats_files" ]]; then
            local file_count
            file_count=$(echo "$bats_files" | wc -l)
            
            if [[ $file_count -gt 0 ]]; then
                results="suites_0_name=bats_tests"
                results="${results}"$'\n'"suites_0_framework=bats"
                results="${results}"$'\n'"suites_0_test_files_count=${file_count}"
                suites_count=1
            fi
        fi
    fi

    # Output results
    echo "suites_count=${suites_count}"
    if [[ -n "$results" ]]; then
        echo "$results"
    fi

    return 0
}

# Detect build requirements for BATS projects
# Usage: detect_build_requirements <project_root> <framework_metadata>
# Returns: Build requirements as flat data
detect_build_requirements() {
    local project_root="$1"
    local framework_metadata="$2"

    # BATS projects typically don't require building (scripts are interpreted)
    echo "requires_build=false"
    echo "build_steps_count=0"
    echo "build_commands_count=0"
    echo "build_dependencies_count=0"
    echo "build_artifacts_count=0"
    return 0
}

# Get build steps for containerized build
# Usage: get_build_steps <project_root> <build_requirements>
# Returns: Build steps as flat data
get_build_steps() {
    local project_root="$1"
    local build_requirements="$2"

    # Stub implementation (no build steps needed for BATS)
    echo "build_steps_count=0"
    return 0
}

# Execute test suite using BATS test runner
# Usage: execute_test_suite <test_suite> <test_image> <execution_config>
# Returns: Execution result as flat data
# Behavior: Executes bats command in container
execute_test_suite() {
    local test_suite="$1"
    local test_image="$2"
    local execution_config="$3"

    # Stub implementation (will be expanded in later phases)
    # For now, return basic structure
    echo "exit_code=0"
    echo "duration=0.0"
    echo "execution_method=docker"
    echo "test_command=bats"
    return 0
}

# Parse test results from BATS test output
# Usage: parse_test_results <output> <exit_code>
# Returns: Parsed results as flat data
# Behavior: Parses bats test output to extract test counts and status
parse_test_results() {
    local output="$1"
    local exit_code="$2"

    # Stub implementation (will be expanded in later phases)
    # For now, return basic structure based on exit code
    if [[ "$exit_code" == "0" ]]; then
        echo "total_tests=0"
        echo "passed_tests=0"
        echo "failed_tests=0"
        echo "skipped_tests=0"
        echo "test_details_count=0"
        echo "status=passed"
    else
        echo "total_tests=0"
        echo "passed_tests=0"
        echo "failed_tests=0"
        echo "skipped_tests=0"
        echo "test_details_count=0"
        echo "status=failed"
    fi

    return 0
}

# Get module metadata
# Usage: get_metadata
# Returns: Module metadata as flat data
get_metadata() {
    echo "module_type=framework"
    echo "language=bash"
    echo "frameworks_0=bats"
    echo "frameworks_count=1"
    echo "project_type=shell_script"
    echo "version=0.1.0"
    echo "capabilities_0=testing"
    echo "capabilities_count=1"
    echo "required_binaries_0=bats"
    echo "required_binaries_count=1"
    return 0
}

