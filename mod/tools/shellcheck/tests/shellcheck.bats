#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the shellcheck module for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../../.." && pwd)"
    cd "$project_root"

    # Source the shellcheck module if it exists
    if [[ -f "mod/tools/shellcheck/mod.sh" ]]; then
        source "mod/tools/shellcheck/mod.sh"
    fi

    # Create a temporary directory with test shell scripts
    export TEST_PROJECT_DIR="$(mktemp -d)"
    echo '#!/bin/bash\necho "test"' > "$TEST_PROJECT_DIR/test.sh"
    echo '#!/bin/bash\necho "another script"' > "$TEST_PROJECT_DIR/script.sh"
    chmod +x "$TEST_PROJECT_DIR"/*.sh
}

teardown() {
    # Clean up temporary directory
    if [[ -d "$TEST_PROJECT_DIR" ]]; then
        rm -rf "$TEST_PROJECT_DIR"
    fi

    # Clean up module functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
}

@test "shellcheck module detect() finds shell scripts" {
    run detect "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "detected=true"
    assert_output --partial "language=shell"
}

@test "shellcheck module detect() returns false for empty directory" {
    local empty_dir="$(mktemp -d)"
    run detect "$empty_dir"
    assert_success
    assert_output --partial "detected=false"
    rm -rf "$empty_dir"
}

@test "shellcheck module discover_test_suites() finds shell scripts" {
    run discover_test_suites "$TEST_PROJECT_DIR" ""
    assert_success
    assert_output --partial "suites_count=1"
    assert_output --partial "suites_0_name=shellcheck"
    assert_output --partial "suites_0_framework=code-quality"
    assert_output --partial "test_files_count=2"
}

@test "shellcheck module get_metadata() returns tool module info" {
    run get_metadata
    assert_success
    assert_output --partial "module_type=tool"
    assert_output --partial "language=shell"
    assert_output --partial "capabilities_0=code-quality"
}

@test "shellcheck module detect_build_requirements() returns no build needed" {
    run detect_build_requirements "$TEST_PROJECT_DIR" ""
    assert_success
    assert_output --partial "requires_build=false"
}

@test "shellcheck module parse_test_results() handles successful results" {
    run parse_test_results "[]" 0
    assert_success
    assert_output --partial "total_tests=1"
    assert_output --partial "passed_tests=1"
    assert_output --partial "status=passed"
}

@test "shellcheck module parse_test_results() handles failed results" {
    run parse_test_results "[]" 1
    assert_success
    assert_output --partial "total_tests=1"
    assert_output --partial "failed_tests=1"
    assert_output --partial "status=failed"
}