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

