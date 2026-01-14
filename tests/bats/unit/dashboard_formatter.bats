#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source required modules
    if [[ -f "src/data_access.sh" ]]; then
        source "src/data_access.sh"
    fi

    if [[ -f "src/dashboard_formatter.sh" ]]; then
        source "src/dashboard_formatter.sh"
    fi

    # Create unique identifier for this test to avoid race conditions
    TEST_UNIQUE_ID="dashboard_${BATS_TEST_NUMBER}_$$_${RANDOM}"

    # Track temporary files for cleanup
    TEST_OUTPUT_FILES=()
}

teardown() {
    # Clean up test output files
    for file in "${TEST_OUTPUT_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    TEST_OUTPUT_FILES=()

    # Clean up files matching our unique ID
    if [[ -n "$TEST_UNIQUE_ID" ]]; then
        rm -f /tmp/*"${TEST_UNIQUE_ID}"* 2>/dev/null || true
    fi

    unset TEST_UNIQUE_ID
}

# =============================================================================
# 4.2.1 Dashboard Display Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Display dashboard header with columns
# -----------------------------------------------------------------------------

@test "format_dashboard_header() displays column headers" {
    run format_dashboard_header
    assert_success
    
    # Should include main column headers
    assert_output --partial "SUITE"
    assert_output --partial "STATUS"
    assert_output --partial "TIME"
}

@test "format_dashboard_header() includes test count columns" {
    run format_dashboard_header
    assert_success
    
    # Should include test count columns
    assert_output --partial "PASS"
    assert_output --partial "FAIL"
    assert_output --partial "TOTAL"
}

@test "format_dashboard_header() includes error/warning columns" {
    run format_dashboard_header
    assert_success
    
    # Should include error and warning columns
    assert_output --partial "ERR"
    assert_output --partial "WARN"
}

@test "format_dashboard_header() includes queue column" {
    run format_dashboard_header
    assert_success
    
    # Should include queue column for pending tests
    assert_output --partial "QUEUE"
}

@test "format_dashboard_header() uses consistent column widths" {
    run format_dashboard_header
    assert_success
    
    # Header should have consistent formatting (column separators)
    assert_output --partial "|"
}

# -----------------------------------------------------------------------------
# Test: Update suite status in real-time
# -----------------------------------------------------------------------------

@test "init_dashboard_state() initializes dashboard tracking" {
    run init_dashboard_state
    assert_success
    
    assert_output --partial "dashboard_initialized=true"
}

@test "register_suite() adds suite to dashboard" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "unit-tests" "pending"
    )
    
    assert [ -n "$(echo "$result" | grep "suite_registered=true")" ]
    assert [ -n "$(echo "$result" | grep "suite_id=unit-tests")" ]
}

@test "update_suite_status() changes suite status" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "unit-tests" "pending" >/dev/null 2>&1
        update_suite_status "unit-tests" "running"
    )
    
    assert [ -n "$(echo "$result" | grep "status_updated=true")" ]
    assert [ -n "$(echo "$result" | grep "new_status=running")" ]
}

@test "get_suite_status() retrieves current status" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "integration-tests" "pending" >/dev/null 2>&1
        update_suite_status "integration-tests" "passed" >/dev/null 2>&1
        get_suite_status "integration-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "status=passed")" ]
}

@test "format_suite_row() formats single suite for display" {
    local suite_data="suite_id=unit-tests
status=running
duration=2.3
queued=0
passed=15
failed=0
total=45
errors=0
warnings=0"
    
    run format_suite_row "$suite_data"
    assert_success
    
    # Should include suite name and status
    assert_output --partial "unit-tests"
    assert_output --partial "running"
    # Should include time
    assert_output --partial "2.3"
}

@test "format_suite_row() handles all valid statuses" {
    # Test pending status
    local pending_data="suite_id=test
status=pending
duration=0
queued=10
passed=0
failed=0
total=10
errors=0
warnings=0"
    
    run format_suite_row "$pending_data"
    assert_success
    assert_output --partial "pending"
    
    # Test passed status
    local passed_data="suite_id=test
status=passed
duration=5.0
queued=0
passed=10
failed=0
total=10
errors=0
warnings=0"
    
    run format_suite_row "$passed_data"
    assert_success
    assert_output --partial "passed"
    
    # Test failed status
    local failed_data="suite_id=test
status=failed
duration=3.0
queued=0
passed=8
failed=2
total=10
errors=0
warnings=0"
    
    run format_suite_row "$failed_data"
    assert_success
    assert_output --partial "failed"
}

@test "format_suite_row() shows test counts" {
    local suite_data="suite_id=unit
status=passed
duration=2.5
queued=0
passed=45
failed=0
total=45
errors=0
warnings=2"
    
    run format_suite_row "$suite_data"
    assert_success
    
    # Should show passed count
    assert_output --partial "45"
}

# -----------------------------------------------------------------------------
# Test: Display build status when builds in progress
# -----------------------------------------------------------------------------

@test "set_build_status() sets build status for suite" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "rust-tests" "pending" >/dev/null 2>&1
        set_build_status "rust-tests" "building"
    )
    
    assert [ -n "$(echo "$result" | grep "build_status_set=true")" ]
}

@test "get_build_status() retrieves build status" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "rust-tests" "pending" >/dev/null 2>&1
        set_build_status "rust-tests" "built" >/dev/null 2>&1
        get_build_status "rust-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "build_status=built")" ]
}

@test "format_suite_row() shows build status when building" {
    local suite_data="suite_id=rust-tests
status=loading
duration=0
queued=0
passed=0
failed=0
total=0
errors=0
warnings=0
build_status=building"
    
    run format_suite_row "$suite_data"
    assert_success
    
    # Should indicate building
    assert_output --partial "building" || assert_output --partial "loading"
}

@test "format_suite_row() shows build-failed status" {
    local suite_data="suite_id=broken-project
status=error
duration=5.0
queued=0
passed=0
failed=0
total=0
errors=1
warnings=0
build_status=build-failed"
    
    run format_suite_row "$suite_data"
    assert_success
    
    # Should indicate build failure
    assert_output --partial "error" || assert_output --partial "build-failed"
}

# -----------------------------------------------------------------------------
# Test: Update test counts as tests complete
# -----------------------------------------------------------------------------

@test "update_suite_counts() updates test counts" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "unit-tests" "running" >/dev/null 2>&1
        update_suite_counts "unit-tests" 20 18 2 0 1
    )
    
    assert [ -n "$(echo "$result" | grep "counts_updated=true")" ]
}

@test "get_suite_counts() retrieves current counts" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "unit-tests" "running" >/dev/null 2>&1
        update_suite_counts "unit-tests" 50 45 5 2 3 >/dev/null 2>&1
        get_suite_counts "unit-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "total=50")" ]
    assert [ -n "$(echo "$result" | grep "passed=45")" ]
    assert [ -n "$(echo "$result" | grep "failed=5")" ]
}

@test "update_suite_duration() updates execution time" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "integration-tests" "running" >/dev/null 2>&1
        update_suite_duration "integration-tests" "3.5"
    )
    
    assert [ -n "$(echo "$result" | grep "duration_updated=true")" ]
}

@test "get_suite_duration() retrieves current duration" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "integration-tests" "running" >/dev/null 2>&1
        update_suite_duration "integration-tests" "7.25" >/dev/null 2>&1
        get_suite_duration "integration-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "duration=7.25")" ]
}

# -----------------------------------------------------------------------------
# Test: Full dashboard rendering
# -----------------------------------------------------------------------------

@test "render_dashboard() displays complete dashboard" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "unit" "passed" >/dev/null 2>&1
        update_suite_counts "unit" 45 45 0 0 0 >/dev/null 2>&1
        update_suite_duration "unit" "2.3" >/dev/null 2>&1
        register_suite "integration" "running" >/dev/null 2>&1
        update_suite_counts "integration" 45 12 0 0 0 >/dev/null 2>&1
        update_suite_duration "integration" "1.1" >/dev/null 2>&1
        render_dashboard
    )
    
    # Should include header
    assert [ -n "$(echo "$result" | grep "SUITE")" ]
    # Should include both suites
    assert [ -n "$(echo "$result" | grep "unit")" ]
    assert [ -n "$(echo "$result" | grep "integration")" ]
}

@test "render_dashboard() shows suites in registration order" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "alpha" "pending" >/dev/null 2>&1
        register_suite "beta" "pending" >/dev/null 2>&1
        register_suite "gamma" "pending" >/dev/null 2>&1
        render_dashboard
    )
    
    # All three should appear
    assert [ -n "$(echo "$result" | grep "alpha")" ]
    assert [ -n "$(echo "$result" | grep "beta")" ]
    assert [ -n "$(echo "$result" | grep "gamma")" ]
}

@test "get_dashboard_state() returns current state summary" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "suite-1" "passed" >/dev/null 2>&1
        register_suite "suite-2" "running" >/dev/null 2>&1
        register_suite "suite-3" "pending" >/dev/null 2>&1
        get_dashboard_state
    )
    
    assert [ -n "$(echo "$result" | grep "total_suites=3")" ]
    assert [ -n "$(echo "$result" | grep "suites_passed=1")" ]
    assert [ -n "$(echo "$result" | grep "suites_running=1")" ]
    assert [ -n "$(echo "$result" | grep "suites_pending=1")" ]
}

@test "clear_dashboard_state() resets all dashboard data" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "suite-1" "passed" >/dev/null 2>&1
        register_suite "suite-2" "failed" >/dev/null 2>&1
        clear_dashboard_state >/dev/null 2>&1
        get_dashboard_state
    )
    
    assert [ -n "$(echo "$result" | grep "total_suites=0")" ]
}

# -----------------------------------------------------------------------------
# Test: Dashboard display formatting
# -----------------------------------------------------------------------------

@test "format_status_indicator() returns appropriate symbol for passed" {
    run format_status_indicator "passed"
    assert_success
    
    # Should indicate success (checkmark or similar)
    assert_output --partial "✓" || assert_output --partial "passed"
}

@test "format_status_indicator() returns appropriate symbol for failed" {
    run format_status_indicator "failed"
    assert_success
    
    # Should indicate failure (X or similar)
    assert_output --partial "✗" || assert_output --partial "failed"
}

@test "format_status_indicator() returns appropriate symbol for running" {
    run format_status_indicator "running"
    assert_success
    
    # Should indicate in progress
    assert_output --partial "⋯" || assert_output --partial "running" || assert_output --partial "►"
}

@test "format_status_indicator() returns appropriate symbol for pending" {
    run format_status_indicator "pending"
    assert_success
    
    # Should indicate waiting
    assert_output --partial "○" || assert_output --partial "pending" || assert_output --partial "⏳"
}

@test "format_duration() formats seconds appropriately" {
    run format_duration "2.5"
    assert_success
    
    assert_output --partial "2.5s" || assert_output --partial "2.5"
}

@test "format_duration() handles zero duration" {
    run format_duration "0"
    assert_success
    
    # Should show something like 0s or -
    assert_output --partial "0" || assert_output --partial "-"
}

@test "format_duration() handles missing duration" {
    run format_duration ""
    assert_success
    
    # Should show placeholder
    assert_output --partial "-" || assert_output --partial "0"
}

# -----------------------------------------------------------------------------
# Test: Edge cases
# -----------------------------------------------------------------------------

@test "register_suite() handles special characters in suite name" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        register_suite "my-suite_v2.0" "pending"
    )
    
    assert [ -n "$(echo "$result" | grep "suite_registered=true")" ]
}

@test "update_suite_status() handles non-existent suite gracefully" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        update_suite_status "nonexistent-suite" "running" || true
    )
    
    # Should indicate suite not found or handle gracefully
    assert [ -n "$(echo "$result" | grep "suite_not_found=true")" ] || \
           [ -n "$(echo "$result" | grep "status_updated=false")" ]
}

@test "render_dashboard() handles empty dashboard" {
    local result
    result=$(
        source src/dashboard_formatter.sh
        init_dashboard_state >/dev/null 2>&1
        render_dashboard
    )
    
    # Should still show header even with no suites
    assert [ -n "$(echo "$result" | grep "SUITE")" ] || \
           [ -n "$(echo "$result" | grep -i "no suites")" ]
}

@test "format_suite_row() truncates long suite names" {
    local suite_data="suite_id=this-is-a-very-long-suite-name-that-exceeds-normal-column-width
status=running
duration=1.0
queued=0
passed=5
failed=0
total=10
errors=0
warnings=0"
    
    run format_suite_row "$suite_data"
    assert_success
    
    # Output should not be excessively wide (reasonable length)
    local line_length
    line_length=$(echo "$output" | head -1 | wc -c)
    assert [ "$line_length" -lt 150 ]
}

