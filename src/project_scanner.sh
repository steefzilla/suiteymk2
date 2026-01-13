#!/usr/bin/env bash

# Project Scanner (Orchestrator)
# Coordinates Platform Detection, Test Suite Detection, and Build System Detection
# Provides unified interface for project analysis

# Source required dependencies
source "src/platform_detector.sh" 2>/dev/null || true
source "src/test_suite_detector.sh" 2>/dev/null || true
source "src/build_system_detector.sh" 2>/dev/null || true
source "src/data_access.sh" 2>/dev/null || true

# Scan project and detect all aspects
# Usage: scan_project <project_root>
# Returns: Unified project scan results in flat data format
# Behavior: Orchestrates all detection phases in correct order
scan_project() {
    local project_root="$1"

    # Validate input
    if [[ -z "$project_root" ]]; then
        echo "Error: Project root is required" >&2
        echo "scan_result=error"
        echo "error_message=Project root is required"
        return 1
    fi

    if [[ ! -d "$project_root" ]]; then
        echo "Error: Project root directory does not exist: $project_root" >&2
        echo "scan_result=error"
        echo "error_message=Project root directory does not exist"
        return 1
    fi

    # Initialize result data
    local result=""
    local scan_success=true

    # Phase 1: Platform Detection
    result=$(data_set "$result" "scan_result" "success")
    result=$(data_set "$result" "project_root" "$project_root")

    echo "Starting platform detection for: $project_root" >&2

    local platform_data
    if platform_data=$(detect_platforms "$project_root" 2>&1); then
        result=$(data_set "$result" "platform_detection_status" "success")
        echo "Platform detection completed successfully" >&2
    else
        result=$(data_set "$result" "platform_detection_status" "failed")
        result=$(data_set "$result" "platform_detection_error" "$platform_data")
        result=$(data_set "$result" "scan_result" "partial")
        scan_success=false
        echo "Platform detection failed: $platform_data" >&2
        # Continue with empty platform data for other phases
        platform_data="platforms_count=0"
    fi

    # Include platform detection results by setting individual fields
    # Parse and set platform data fields
    while IFS='=' read -r key value; do
        if [[ -n "$key" && "$key" != "platform_detection_status" ]]; then
            result=$(data_set "$result" "$key" "$value")
        fi
    done <<< "$platform_data"

    # Phase 2: Test Suite Detection (depends on platform detection)
    echo "Starting test suite detection" >&2

    local suite_data
    if suite_data=$(discover_test_suites "$platform_data" 2>&1); then
        result=$(data_set "$result" "test_suite_detection_status" "success")
        echo "Test suite detection completed successfully" >&2
    else
        result=$(data_set "$result" "test_suite_detection_status" "failed")
        result=$(data_set "$result" "test_suite_detection_error" "$suite_data")
        result=$(data_set "$result" "scan_result" "partial")
        scan_success=false
        echo "Test suite detection failed: $suite_data" >&2
        # Continue with empty suite data
        suite_data="suites_count=0"
    fi

    # Include test suite detection results by setting individual fields
    while IFS='=' read -r key value; do
        if [[ -n "$key" && "$key" != "test_suite_detection_status" ]]; then
            result=$(data_set "$result" "$key" "$value")
        fi
    done <<< "$suite_data"

    # Phase 3: Build System Detection (depends on platform detection)
    echo "Starting build system detection" >&2

    local build_data
    if build_data=$(detect_build_requirements "$platform_data" 2>&1); then
        result=$(data_set "$result" "build_system_detection_status" "success")
        echo "Build system detection completed successfully" >&2
    else
        result=$(data_set "$result" "build_system_detection_status" "failed")
        result=$(data_set "$result" "build_system_detection_error" "$build_data")
        result=$(data_set "$result" "scan_result" "partial")
        scan_success=false
        echo "Build system detection failed: $build_data" >&2
        # Continue with safe defaults
        build_data="requires_build=false"$'\n'"build_commands_count=0"$'\n'"build_dependencies_count=0"$'\n'"build_artifacts_count=0"
    fi

    # Include build system detection results by setting individual fields
    while IFS='=' read -r key value; do
        if [[ -n "$key" && "$key" != "build_system_detection_status" ]]; then
            result=$(data_set "$result" "$key" "$value")
        fi
    done <<< "$build_data"

    # Phase 4: Build Steps Detection (depends on build requirements)
    echo "Starting build steps detection" >&2

    local build_steps_data
    if build_steps_data=$(get_build_steps "$platform_data" "$build_data" 2>&1); then
        result=$(data_set "$result" "build_steps_detection_status" "success")
        echo "Build steps detection completed successfully" >&2
    else
        result=$(data_set "$result" "build_steps_detection_status" "failed")
        result=$(data_set "$result" "build_steps_detection_error" "$build_steps_data")
        result=$(data_set "$result" "scan_result" "partial")
        scan_success=false
        echo "Build steps detection failed: $build_steps_data" >&2
        # Continue with empty build steps
        build_steps_data="build_steps_count=0"
    fi

    # Include build steps detection results by setting individual fields
    while IFS='=' read -r key value; do
        if [[ -n "$key" && "$key" != "build_steps_detection_status" ]]; then
            result=$(data_set "$result" "$key" "$value")
        fi
    done <<< "$build_steps_data"

    # Phase 5: Build Dependency Analysis (depends on build steps)
    echo "Starting build dependency analysis" >&2

    local dependency_data
    if dependency_data=$(analyze_build_dependencies "$build_steps_data" 2>&1); then
        result=$(data_set "$result" "build_dependency_analysis_status" "success")
        echo "Build dependency analysis completed successfully" >&2
    else
        result=$(data_set "$result" "build_dependency_analysis_status" "failed")
        result=$(data_set "$result" "build_dependency_analysis_error" "$dependency_data")
        result=$(data_set "$result" "scan_result" "partial")
        scan_success=false
        echo "Build dependency analysis failed: $dependency_data" >&2
        # Continue with safe defaults
        dependency_data="execution_order_count=0"$'\n'"parallel_groups_count=0"$'\n'"dependency_graph_count=0"
    fi

    # Include build dependency analysis results by setting individual fields
    while IFS='=' read -r key value; do
        if [[ -n "$key" && "$key" != "build_dependency_analysis_status" ]]; then
            result=$(data_set "$result" "$key" "$value")
        fi
    done <<< "$dependency_data"

    # Final status
    if [[ "$scan_success" == true ]]; then
        result=$(data_set "$result" "scan_result" "success")
        echo "Project scan completed successfully" >&2
    else
        echo "Project scan completed with partial failures" >&2
    fi

    echo "$result"
    return 0
}
