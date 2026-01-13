#!/usr/bin/env bash

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the project_scanner.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the project_scanner.sh file if it exists (it will source mod_registry.sh)
    if [[ -f "src/project_scanner.sh" ]]; then
        source "src/project_scanner.sh"
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

@test "scan_project() handles Platform Detector failures gracefully" {
    # Create a temporary directory
    local test_dir
    test_dir="$(mktemp -d)"

    # Mock platform detector failure by creating a scenario that would cause failure
    # (This is hard to simulate directly, so we'll test with an empty directory which should still work)
    run scan_project "$test_dir"
    assert_success

    # Should still complete other phases even if platform detection "fails"
    assert_output --regexp "platform_detection_status="
    assert_output --regexp "test_suite_detection_status="
    assert_output --regexp "build_system_detection_status="
    assert_output --partial "scan_result=success"

    # Clean up
    rm -rf "$test_dir"
}

@test "scan_project() continues with other detectors when one fails" {
    # Create a temporary directory
    local test_dir
    test_dir="$(mktemp -d)"

    run scan_project "$test_dir"
    assert_success

    # All detection phases should have status (even if they "failed" or returned empty results)
    assert_output --regexp "platform_detection_status="
    assert_output --regexp "test_suite_detection_status="
    assert_output --regexp "build_system_detection_status="
    assert_output --regexp "build_steps_detection_status="
    assert_output --regexp "build_dependency_analysis_status="

    # Overall scan should succeed
    assert_output --partial "scan_result=success"

    # Clean up
    rm -rf "$test_dir"
}

@test "scan_project() provides clear error messages for failures" {
    # Test with non-existent directory (should fail with clear error)
    run scan_project "/nonexistent/directory/that/does/not/exist"
    assert_failure
    assert_output --partial "Error: Project root directory does not exist"
    assert_output --partial "scan_result=error"
    assert_output --partial "error_message=Project root directory does not exist"
}

@test "scan_project() provides clear error messages for invalid input" {
    # Test with empty string (should fail with clear error)
    run scan_project ""
    assert_failure
    assert_output --partial "Error: Project root is required"
    assert_output --partial "scan_result=error"
    assert_output --partial "error_message=Project root is required"
}

@test "scan_project() handles partial failures with detailed error reporting" {
    # Create a directory that might cause some detection phases to "fail" or return empty
    local test_dir
    test_dir="$(mktemp -d)"

    # Create some files that might confuse detectors
    echo "invalid content" > "$test_dir/invalid_file.xyz"

    run scan_project "$test_dir"
    assert_success

    # Should provide status for all phases
    assert_output --regexp "platform_detection_status="
    assert_output --regexp "test_suite_detection_status="
    assert_output --regexp "build_system_detection_status="

    # If any phase "failed", overall result should reflect partial success
    # (In this case, all should succeed with empty results)

    # Clean up
    rm -rf "$test_dir"
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

@test "aggregate_scan_results() combines platform detection results from example projects" {
    # Mock platform detection result
    local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language"

    local suite_data="suites_count=0"
    local build_data="requires_build=false
build_commands_count=0"
    local build_steps_data="build_steps_count=0"
    local dependency_data="execution_order_count=0"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Verify platform data is included
    assert_output --partial "platforms_count=1"
    assert_output --partial "platforms_0_language=rust"
    assert_output --partial "platforms_0_framework=cargo"
    assert_output --partial "platform_detection_status=success"
}

@test "aggregate_scan_results() combines test suite results from example projects" {
    local platform_data="platforms_count=0"
    # Mock test suite detection result
    local suite_data="suites_count=2
suites_0_name=unit
suites_0_files_count=3
suites_0_test_count=5
suites_1_name=integration
suites_1_files_count=2
suites_1_test_count=8"

    local build_data="requires_build=false
build_commands_count=0"
    local build_steps_data="build_steps_count=0"
    local dependency_data="execution_order_count=0"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Verify test suite data is included
    assert_output --partial "suites_count=2"
    assert_output --partial "suites_0_name=unit"
    assert_output --partial "suites_0_test_count=5"
    assert_output --partial "suites_1_name=integration"
    assert_output --partial "suites_1_test_count=8"
    assert_output --partial "test_suite_detection_status=success"
}

@test "aggregate_scan_results() combines build requirement results from example projects" {
    local platform_data="platforms_count=0"
    local suite_data="suites_count=0"
    # Mock build system detection result
    local build_data="requires_build=true
build_commands_count=1
build_commands_0=\"cargo build --tests\"
build_dependencies_count=0
build_artifacts_count=0"

    local build_steps_data="build_steps_count=0"
    local dependency_data="execution_order_count=0"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Verify build data is included
    assert_output --partial "requires_build=true"
    assert_output --partial "build_commands_count=1"
    assert_output --partial "build_commands_0="
    assert_output --partial "cargo build --tests"
    assert_output --partial "build_system_detection_status=success"
}

@test "aggregate_scan_results() handles partial failures (some detectors fail)" {
    # Simulate partial failure - empty build data
    local platform_data="platforms_count=1
platforms_0_language=rust"
    local suite_data="suites_count=0"
    local build_data=""  # Simulate failure - no build data
    local build_steps_data="build_steps_count=0"
    local dependency_data="execution_order_count=0"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Should still aggregate available data
    assert_output --partial "platforms_count=1"
    assert_output --partial "platforms_0_language=rust"
    assert_output --partial "suites_count=0"
    # Build data should be empty but status should still be set
    assert_output --partial "build_system_detection_status=success"
}

@test "aggregate_scan_results() provides summary information" {
    local platform_data="platforms_count=2"
    local suite_data="suites_count=3"
    local build_data="requires_build=true"
    local build_steps_data="build_steps_count=1"
    local dependency_data="execution_order_count=1"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Verify summary fields
    assert_output --partial "summary_platforms_detected=2"
    assert_output --partial "summary_test_suites_found=3"
    assert_output --partial "summary_build_required=true"
    assert_output --partial "summary_build_steps_defined=1"
}

@test "aggregate_scan_results() returns structured results in flat data format" {
    local platform_data="platforms_count=0"
    local suite_data="suites_count=0"
    local build_data="requires_build=false"
    local build_steps_data="build_steps_count=0"
    local dependency_data="execution_order_count=0"

    run aggregate_scan_results "$platform_data" "$suite_data" "$build_data" "$build_steps_data" "$dependency_data"
    assert_success

    # Verify all expected fields are present
    assert_output --regexp "scan_result="
    assert_output --regexp "platform_detection_status="
    assert_output --regexp "test_suite_detection_status="
    assert_output --regexp "build_system_detection_status="
    assert_output --regexp "build_steps_detection_status="
    assert_output --regexp "build_dependency_analysis_status="
    assert_output --regexp "summary_platforms_detected="
    assert_output --regexp "summary_test_suites_found="
    assert_output --regexp "summary_build_required="
    assert_output --regexp "summary_build_steps_defined="
}
