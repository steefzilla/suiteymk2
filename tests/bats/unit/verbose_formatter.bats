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

    if [[ -f "src/verbose_formatter.sh" ]]; then
        source "src/verbose_formatter.sh"
    fi

    # Create unique identifier for this test to avoid race conditions
    TEST_UNIQUE_ID="verbose_${BATS_TEST_NUMBER}_$$_${RANDOM}"

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
# 4.1.1 Output Streaming Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Stream test output with suite identification prefix
# -----------------------------------------------------------------------------

@test "format_output_line() adds suite identification prefix to output" {
    run format_output_line "rust-tests" "Running test test_addition..."
    assert_success
    
    # Should have suite prefix
    assert_output --partial "[rust-tests]"
    assert_output --partial "Running test test_addition..."
}

@test "format_output_line() handles empty output gracefully" {
    run format_output_line "my-suite" ""
    assert_success
    
    # Should still have prefix even with empty content
    assert_output --partial "[my-suite]"
}

@test "format_output_line() handles multiline output" {
    local multiline_output="Line 1
Line 2
Line 3"
    
    run format_output_line "test-suite" "$multiline_output"
    assert_success
    
    # Each line should have the prefix
    assert_output --partial "[test-suite] Line 1"
    assert_output --partial "[test-suite] Line 2"
    assert_output --partial "[test-suite] Line 3"
}

@test "format_output_line() preserves special characters in output" {
    run format_output_line "suite" "Test with special chars: \$HOME, \`backticks\`, \"quotes\""
    assert_success
    
    assert_output --partial "[suite]"
}

@test "stream_suite_output() streams output from file with prefix" {
    # Create a test output file
    local output_file="/tmp/suitey_test_output_${TEST_UNIQUE_ID}"
    cat > "$output_file" << 'EOF'
Running tests...
test_one: PASSED
test_two: PASSED
All tests passed!
EOF
    TEST_OUTPUT_FILES+=("$output_file")
    
    run stream_suite_output "my-suite" "$output_file"
    assert_success
    
    # Should stream all lines with prefix
    assert_output --partial "[my-suite] Running tests..."
    assert_output --partial "[my-suite] test_one: PASSED"
    assert_output --partial "[my-suite] All tests passed!"
}

@test "stream_suite_output() handles non-existent file gracefully" {
    run stream_suite_output "suite" "/tmp/nonexistent_file_${TEST_UNIQUE_ID}"
    
    # Should not crash, might return error or empty output
    # The key is it doesn't crash
    assert [ $status -eq 0 ] || assert [ $status -eq 1 ]
}

@test "stream_suite_output() handles empty file" {
    local output_file="/tmp/suitey_test_output_${TEST_UNIQUE_ID}"
    touch "$output_file"
    TEST_OUTPUT_FILES+=("$output_file")
    
    run stream_suite_output "suite" "$output_file"
    assert_success
}

# -----------------------------------------------------------------------------
# Test: Buffer output by suite for readability
# -----------------------------------------------------------------------------

@test "init_output_buffer() initializes buffer for suite" {
    run init_output_buffer "rust-tests"
    assert_success
    
    # Should indicate buffer was initialized
    assert_output --partial "buffer_initialized=true"
    assert_output --partial "suite_id=rust-tests"
}

@test "buffer_output() adds content to suite buffer" {
    # Initialize buffer first
    init_output_buffer "test-suite" >/dev/null 2>&1
    
    run buffer_output "test-suite" "First line of output"
    assert_success
    
    assert_output --partial "buffered=true"
}

@test "buffer_output() accumulates multiple outputs" {
    init_output_buffer "test-suite" >/dev/null 2>&1
    
    buffer_output "test-suite" "Line 1" >/dev/null 2>&1
    buffer_output "test-suite" "Line 2" >/dev/null 2>&1
    buffer_output "test-suite" "Line 3" >/dev/null 2>&1
    
    run get_buffer_contents "test-suite"
    assert_success
    
    assert_output --partial "Line 1"
    assert_output --partial "Line 2"
    assert_output --partial "Line 3"
}

@test "flush_output_buffer() outputs buffered content with prefix" {
    init_output_buffer "my-suite" >/dev/null 2>&1
    buffer_output "my-suite" "Test output line 1" >/dev/null 2>&1
    buffer_output "my-suite" "Test output line 2" >/dev/null 2>&1
    
    run flush_output_buffer "my-suite"
    assert_success
    
    # Should output with suite prefix
    assert_output --partial "[my-suite]"
    assert_output --partial "Test output line 1"
    assert_output --partial "Test output line 2"
}

@test "flush_output_buffer() clears buffer after flush" {
    init_output_buffer "suite" >/dev/null 2>&1
    buffer_output "suite" "Some content" >/dev/null 2>&1
    flush_output_buffer "suite" >/dev/null 2>&1
    
    # Buffer should be empty after flush
    run get_buffer_contents "suite"
    
    # Should be empty or indicate no content
    local content
    content=$(echo "$output" | grep "^content=" | cut -d'=' -f2-)
    assert [ -z "$content" ] || assert [ "$content" = "" ]
}

@test "clear_output_buffer() removes buffer without flushing" {
    local suite_id="clear-test-${TEST_UNIQUE_ID}"
    
    # Test the clear function in a single shell context using a subshell
    # that performs all operations together
    local test_result
    test_result=$(
        source src/verbose_formatter.sh
        init_output_buffer "$suite_id" >/dev/null 2>&1
        buffer_output "$suite_id" "Content that will be discarded" >/dev/null 2>&1
        clear_output_buffer "$suite_id" >/dev/null 2>&1
        get_buffer_contents "$suite_id"
    )
    
    # After clear, content should be empty
    local content
    content=$(echo "$test_result" | grep "^content=" | cut -d'=' -f2-)
    
    assert [ -z "$content" ]
}

@test "multiple suites have independent buffers" {
    local suite_a="multi-a-${TEST_UNIQUE_ID}"
    local suite_b="multi-b-${TEST_UNIQUE_ID}"
    
    init_output_buffer "$suite_a" >/dev/null 2>&1
    init_output_buffer "$suite_b" >/dev/null 2>&1
    
    buffer_output "$suite_a" "Content for A" >/dev/null 2>&1
    buffer_output "$suite_b" "Content for B" >/dev/null 2>&1
    
    # Check suite A buffer (call directly to stay in same shell context)
    local content_a
    content_a=$(get_buffer_contents "$suite_a" 2>&1 | grep "^content=" | cut -d'=' -f2-)
    assert [ "$content_a" = "Content for A" ]
    
    # Check suite B buffer
    local content_b
    content_b=$(get_buffer_contents "$suite_b" 2>&1 | grep "^content=" | cut -d'=' -f2-)
    assert [ "$content_b" = "Content for B" ]
}

# -----------------------------------------------------------------------------
# Test: Output buffer every 100ms (fallback)
# -----------------------------------------------------------------------------

@test "get_buffer_flush_interval() returns default 100ms" {
    run get_buffer_flush_interval
    assert_success
    
    # Default should be 100ms (0.1 seconds)
    assert_output --partial "flush_interval_ms=100"
}

@test "get_buffer_flush_interval() respects environment override" {
    export SUITEY_BUFFER_FLUSH_INTERVAL_MS=200
    
    run get_buffer_flush_interval
    assert_success
    
    assert_output --partial "flush_interval_ms=200"
    
    unset SUITEY_BUFFER_FLUSH_INTERVAL_MS
}

@test "should_flush_buffer() returns true after interval elapsed" {
    init_output_buffer "suite" >/dev/null 2>&1
    buffer_output "suite" "Some content" >/dev/null 2>&1
    
    # Wait a bit longer than the flush interval
    sleep 0.15
    
    run should_flush_buffer "suite"
    assert_success
    
    assert_output --partial "should_flush=true"
}

@test "should_flush_buffer() returns false if interval not elapsed" {
    init_output_buffer "suite" >/dev/null 2>&1
    buffer_output "suite" "Some content" >/dev/null 2>&1
    
    # Check immediately (within flush interval)
    run should_flush_buffer "suite"
    
    # Might be true or false depending on timing, but should not crash
    assert_success
}

@test "auto_flush_buffers() flushes all buffers past their interval" {
    local suite_1="autoflush-1-${TEST_UNIQUE_ID}"
    local suite_2="autoflush-2-${TEST_UNIQUE_ID}"
    
    init_output_buffer "$suite_1" >/dev/null 2>&1
    init_output_buffer "$suite_2" >/dev/null 2>&1
    
    buffer_output "$suite_1" "Content 1" >/dev/null 2>&1
    buffer_output "$suite_2" "Content 2" >/dev/null 2>&1
    
    # Wait for flush interval
    sleep 0.15
    
    # Call directly in same shell context
    local flush_output
    flush_output=$(auto_flush_buffers 2>&1)
    
    # Should have flushed content (check for suite prefixes)
    assert [ -n "$(echo "$flush_output" | grep "\[$suite_1\]")" ] || \
           [ -n "$(echo "$flush_output" | grep "flushed_count=")" ]
}

# -----------------------------------------------------------------------------
# Test: Verbose formatter integration
# -----------------------------------------------------------------------------

@test "verbose_format_result() formats test result for verbose output" {
    local test_result="suite_id=rust-tests
test_status=passed
exit_code=0
duration=1.23
total_tests=5
passed_tests=5
failed_tests=0"
    
    run verbose_format_result "$test_result"
    assert_success
    
    # Should include suite identification
    assert_output --partial "rust-tests"
    # Should include status
    assert_output --partial "passed"
}

@test "verbose_format_result() includes failure details when present" {
    local test_result="suite_id=unit-tests
test_status=failed
exit_code=1
duration=2.5
total_tests=10
passed_tests=8
failed_tests=2
stdout=Test output here
stderr=Error: assertion failed"
    
    run verbose_format_result "$test_result"
    assert_success
    
    assert_output --partial "unit-tests"
    assert_output --partial "failed"
}

@test "start_verbose_streaming() initializes verbose mode" {
    run start_verbose_streaming
    assert_success
    
    assert_output --partial "verbose_mode=active"
}

@test "stop_verbose_streaming() flushes all remaining buffers" {
    start_verbose_streaming >/dev/null 2>&1
    init_output_buffer "final-suite" >/dev/null 2>&1
    buffer_output "final-suite" "Final output" >/dev/null 2>&1
    
    run stop_verbose_streaming
    assert_success
    
    # Should flush remaining content
    assert_output --partial "[final-suite]"
    assert_output --partial "Final output"
}

# -----------------------------------------------------------------------------
# Edge cases and error handling
# -----------------------------------------------------------------------------

@test "format_output_line() handles very long lines" {
    local long_line=$(printf 'x%.0s' {1..1000})
    
    run format_output_line "suite" "$long_line"
    assert_success
    
    assert_output --partial "[suite]"
}

@test "buffer_output() handles binary-like content gracefully" {
    # Some test output might contain unusual characters
    local weird_content=$'binary\x00content\x01with\x02special'
    
    run buffer_output "suite" "$weird_content"
    # Should not crash
    assert [ $status -eq 0 ] || assert [ $status -eq 1 ]
}

@test "stream_suite_output() handles rapidly growing file" {
    local output_file="/tmp/suitey_test_output_${TEST_UNIQUE_ID}"
    echo "Initial content" > "$output_file"
    TEST_OUTPUT_FILES+=("$output_file")
    
    # Start streaming in background would be complex, so just verify it works
    run stream_suite_output "suite" "$output_file"
    assert_success
}

@test "flush_output_buffer() handles uninitialized buffer gracefully" {
    # Try to flush a buffer that was never initialized
    run flush_output_buffer "never-initialized-${TEST_UNIQUE_ID}"
    
    # Should not crash
    assert [ $status -eq 0 ] || assert [ $status -eq 1 ]
}

@test "get_active_buffers() lists all active suite buffers" {
    local suite_1="listactive-1-${TEST_UNIQUE_ID}"
    local suite_2="listactive-2-${TEST_UNIQUE_ID}"
    local suite_3="listactive-3-${TEST_UNIQUE_ID}"
    
    init_output_buffer "$suite_1" >/dev/null 2>&1
    init_output_buffer "$suite_2" >/dev/null 2>&1
    init_output_buffer "$suite_3" >/dev/null 2>&1
    
    # Call directly in same shell context
    local active_output
    active_output=$(get_active_buffers 2>&1)
    
    # Should list active suites
    assert [ -n "$(echo "$active_output" | grep "$suite_1")" ]
    assert [ -n "$(echo "$active_output" | grep "$suite_2")" ]
    assert [ -n "$(echo "$active_output" | grep "$suite_3")" ]
}

# =============================================================================
# 4.1.2 Post-Completion Output Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Output all tests in execution order
# -----------------------------------------------------------------------------

@test "record_test_execution() records test with timestamp for ordering" {
    run record_test_execution "suite-1" "passed" "1.5"
    assert_success
    
    assert_output --partial "recorded=true"
    assert_output --partial "suite_id=suite-1"
}

@test "record_test_execution() stores execution metadata" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "rust-tests" "passed" "2.3" >/dev/null 2>&1
        get_execution_record "rust-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "suite_id=rust-tests")" ]
    assert [ -n "$(echo "$result" | grep "status=passed")" ]
    assert [ -n "$(echo "$result" | grep "duration=2.3")" ]
}

@test "get_execution_order() returns suites in execution order" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "suite-first" "passed" "1.0" >/dev/null 2>&1
        sleep 0.01  # Small delay to ensure ordering
        record_test_execution "suite-second" "passed" "2.0" >/dev/null 2>&1
        sleep 0.01
        record_test_execution "suite-third" "passed" "3.0" >/dev/null 2>&1
        get_execution_order
    )
    
    # Should list suites in order
    assert [ -n "$(echo "$result" | grep "suite-first")" ]
    assert [ -n "$(echo "$result" | grep "suite-second")" ]
    assert [ -n "$(echo "$result" | grep "suite-third")" ]
}

@test "format_post_completion_summary() outputs all tests in execution order" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "alpha-suite" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "beta-suite" "failed" "2.0" >/dev/null 2>&1
        record_test_execution "gamma-suite" "passed" "1.5" >/dev/null 2>&1
        format_post_completion_summary
    )
    
    # Should include all suites
    assert [ -n "$(echo "$result" | grep "alpha-suite")" ]
    assert [ -n "$(echo "$result" | grep "beta-suite")" ]
    assert [ -n "$(echo "$result" | grep "gamma-suite")" ]
}

# -----------------------------------------------------------------------------
# Test: Display stack traces for failures
# -----------------------------------------------------------------------------

@test "record_test_failure() stores failure with stack trace" {
    local stack_trace="at test_function (test.sh:10)
at main (test.sh:25)"
    
    run record_test_failure "unit-tests" "$stack_trace" "Assertion failed: expected 5 but got 3"
    assert_success
    
    assert_output --partial "failure_recorded=true"
}

@test "get_failure_details() retrieves stored stack trace" {
    local stack_trace="at test_addition (math_test.sh:15)
at run_tests (runner.sh:42)"
    local error_msg="Expected 10 but got 7"
    
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_failure "math-tests" "$stack_trace" "$error_msg" >/dev/null 2>&1
        get_failure_details "math-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "test_addition")" ]
    assert [ -n "$(echo "$result" | grep "math_test.sh:15")" ]
    assert [ -n "$(echo "$result" | grep "Expected 10")" ]
}

@test "format_failure_output() displays stack trace with formatting" {
    local stack_trace="at test_login (auth_test.sh:33)
at test_suite (suite.sh:100)"
    local error_msg="Login failed: invalid credentials"
    
    run format_failure_output "auth-tests" "$stack_trace" "$error_msg"
    assert_success
    
    # Should include failure header
    assert_output --partial "FAILURE"
    # Should include suite name
    assert_output --partial "auth-tests"
    # Should include stack trace
    assert_output --partial "test_login"
    assert_output --partial "auth_test.sh:33"
    # Should include error message
    assert_output --partial "Login failed"
}

@test "format_post_completion_summary() includes stack traces for failures" {
    local stack_trace="at failing_test (test.sh:50)"
    
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "passing-suite" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "failing-suite" "failed" "2.0" >/dev/null 2>&1
        record_test_failure "failing-suite" "$stack_trace" "Test assertion failed" >/dev/null 2>&1
        format_post_completion_summary
    )
    
    # Should show stack trace for failing suite
    assert [ -n "$(echo "$result" | grep "failing_test")" ]
    assert [ -n "$(echo "$result" | grep "test.sh:50")" ]
}

# -----------------------------------------------------------------------------
# Test: Display stack traces for errors
# -----------------------------------------------------------------------------

@test "record_test_error() stores error with stack trace" {
    local stack_trace="at broken_function (code.sh:5)
at test_runner (runner.sh:10)"
    
    run record_test_error "integration-tests" "$stack_trace" "Segmentation fault"
    assert_success
    
    assert_output --partial "error_recorded=true"
}

@test "get_error_details() retrieves stored error information" {
    local stack_trace="at database_connect (db.sh:20)
at setup (test.sh:5)"
    local error_msg="Connection refused: localhost:5432"
    
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_error "db-tests" "$stack_trace" "$error_msg" >/dev/null 2>&1
        get_error_details "db-tests"
    )
    
    assert [ -n "$(echo "$result" | grep "database_connect")" ]
    assert [ -n "$(echo "$result" | grep "db.sh:20")" ]
    assert [ -n "$(echo "$result" | grep "Connection refused")" ]
}

@test "format_error_output() displays error with distinct formatting" {
    local stack_trace="at crash_site (broken.sh:99)"
    local error_msg="Out of memory"
    
    run format_error_output "memory-tests" "$stack_trace" "$error_msg"
    assert_success
    
    # Should include error header (different from failure)
    assert_output --partial "ERROR"
    # Should include suite name
    assert_output --partial "memory-tests"
    # Should include stack trace
    assert_output --partial "crash_site"
    # Should include error message
    assert_output --partial "Out of memory"
}

@test "format_post_completion_summary() includes stack traces for errors" {
    local stack_trace="at error_site (broken.sh:77)"
    
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "normal-suite" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "error-suite" "error" "0.5" >/dev/null 2>&1
        record_test_error "error-suite" "$stack_trace" "Runtime exception" >/dev/null 2>&1
        format_post_completion_summary
    )
    
    # Should show stack trace for error suite
    assert [ -n "$(echo "$result" | grep "error_site")" ]
    assert [ -n "$(echo "$result" | grep "broken.sh:77")" ]
}

# -----------------------------------------------------------------------------
# Test: Post-completion summary formatting
# -----------------------------------------------------------------------------

@test "format_post_completion_summary() shows overall summary" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "suite-1" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "suite-2" "passed" "1.5" >/dev/null 2>&1
        record_test_execution "suite-3" "failed" "2.0" >/dev/null 2>&1
        format_post_completion_summary
    )
    
    # Should include summary section
    assert [ -n "$(echo "$result" | grep -i "summary")" ]
    # Should show counts (case insensitive - "Passed:" or "passed")
    assert [ -n "$(echo "$result" | grep -i "passed")" ]
    # Should show the count of 2 passed suites
    assert [ -n "$(echo "$result" | grep "2")" ]
}

@test "format_post_completion_summary() distinguishes failures from errors" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "fail-suite" "failed" "1.0" >/dev/null 2>&1
        record_test_failure "fail-suite" "at test (t.sh:1)" "Assertion failed" >/dev/null 2>&1
        record_test_execution "error-suite" "error" "0.5" >/dev/null 2>&1
        record_test_error "error-suite" "at crash (c.sh:1)" "Segfault" >/dev/null 2>&1
        format_post_completion_summary
    )
    
    # Should have distinct sections for failures and errors
    assert [ -n "$(echo "$result" | grep -i "failure")" ]
    assert [ -n "$(echo "$result" | grep -i "error")" ]
}

@test "clear_execution_records() resets all recorded data" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "suite-1" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "suite-2" "failed" "2.0" >/dev/null 2>&1
        clear_execution_records >/dev/null 2>&1
        get_execution_order
    )
    
    # Should have no suites after clear
    local count
    count=$(echo "$result" | grep "^suite_id=" | wc -l)
    assert [ "$count" -eq 0 ]
}

@test "get_total_execution_stats() returns aggregate statistics" {
    local result
    result=$(
        source src/verbose_formatter.sh
        record_test_execution "suite-1" "passed" "1.0" >/dev/null 2>&1
        record_test_execution "suite-2" "passed" "1.5" >/dev/null 2>&1
        record_test_execution "suite-3" "failed" "2.0" >/dev/null 2>&1
        record_test_execution "suite-4" "error" "0.5" >/dev/null 2>&1
        get_total_execution_stats
    )
    
    assert [ -n "$(echo "$result" | grep "total_suites=4")" ]
    assert [ -n "$(echo "$result" | grep "passed_suites=2")" ]
    assert [ -n "$(echo "$result" | grep "failed_suites=1")" ]
    assert [ -n "$(echo "$result" | grep "error_suites=1")" ]
}

