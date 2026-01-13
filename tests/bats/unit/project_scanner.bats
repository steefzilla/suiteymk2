#!/usr/bin/env bash

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the project_scanner.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the project_scanner.sh file if it exists
    if [[ -f "src/project_scanner.sh" ]]; then
        source "src/project_scanner.sh"
    fi

    # Source other required modules for integration testing
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
    fi
}

teardown() {
    # Clean up any module functions that were defined
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
}

@test "scan_project() validates input parameters" {
    # Test missing project root
    run scan_project ""
    assert_failure
    assert_output --partial "Error: Project root is required"
    assert_output --partial "scan_result=error"

    # Test non-existent directory
    run scan_project "/nonexistent/directory"
    assert_failure
    assert_output --partial "Project root directory does not exist"
    assert_output --partial "scan_result=error"
}

@test "scan_project() orchestrates platform detection on Rust example project" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success
        assert_output --partial "scan_result=success"
        assert_output --partial "platform_detection_status=success"
        assert_output --partial "platforms_count="
        assert_output --partial "project_root=example/rust-project"
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() orchestrates platform detection on BATS example project" {
    if [[ -d "example/bats-project" ]]; then
        run scan_project "example/bats-project"
        assert_success
        assert_output --partial "scan_result=success"
        assert_output --partial "platform_detection_status=success"
        assert_output --partial "platforms_count="
        assert_output --partial "project_root=example/bats-project"
    else
        skip "example/bats-project not available"
    fi
}

@test "scan_project() orchestrates test suite detection after platform detection" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success
        assert_output --partial "test_suite_detection_status=success"
        assert_output --partial "suites_count="
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() orchestrates build system detection after platform detection" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success
        assert_output --partial "build_system_detection_status=success"
        assert_output --partial "requires_build="
        assert_output --partial "build_commands_count="
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() orchestrates build steps detection" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success
        assert_output --partial "build_steps_detection_status=success"
        assert_output --partial "build_steps_count="
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() orchestrates build dependency analysis" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success
        assert_output --partial "build_dependency_analysis_status=success"
        assert_output --partial "execution_order_count="
        assert_output --partial "parallel_groups_count="
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() aggregates results from all detectors" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success

        # Verify all detection phases are included
        assert_output --regexp "platform_detection_status="
        assert_output --regexp "test_suite_detection_status="
        assert_output --regexp "build_system_detection_status="
        assert_output --regexp "build_steps_detection_status="
        assert_output --regexp "build_dependency_analysis_status="

        # Verify aggregated data is present
        assert_output --regexp "platforms_count="
        assert_output --regexp "suites_count="
        assert_output --regexp "requires_build="
        assert_output --regexp "build_steps_count="
        assert_output --regexp "execution_order_count="
    else
        skip "example/rust-project not available"
    fi
}

@test "scan_project() handles detection failures gracefully" {
    # Create a temporary directory with no detectable platforms
    local empty_dir
    empty_dir="$(mktemp -d)"

    run scan_project "$empty_dir"
    assert_success
    assert_output --partial "scan_result=success"

    # Even with no detectable platforms, all phases should complete
    assert_output --regexp "platform_detection_status="
    assert_output --regexp "test_suite_detection_status="
    assert_output --regexp "build_system_detection_status="

    # Clean up
    rm -rf "$empty_dir"
}

@test "scan_project() returns structured results in flat data format" {
    if [[ -d "example/rust-project" ]]; then
        run scan_project "example/rust-project"
        assert_success

        # Verify essential fields are present
        assert_output --regexp "scan_result="
        assert_output --regexp "project_root="
        assert_output --regexp "platform_detection_status="
        assert_output --regexp "test_suite_detection_status="
        assert_output --regexp "build_system_detection_status="
    else
        skip "example/rust-project not available"
    fi
}
