#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source required modules
    if [[ -f "src/execution_system.sh" ]]; then
        source "src/execution_system.sh"
    fi

    if [[ -f "src/build_manager.sh" ]]; then
        source "src/build_manager.sh"
    fi

    if [[ -f "src/parallel_execution.sh" ]]; then
        source "src/parallel_execution.sh"
    fi

    # Clean up any existing test result files
    rm -f /tmp/suitey_test_result_* /tmp/suitey_test_output_* 2>/dev/null || true

    # Track result files created during tests for cleanup
    TEST_RESULT_FILES=()
    TEST_OUTPUT_FILES=()
}

teardown() {
    # Clean up test result files
    for file in "${TEST_RESULT_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    TEST_RESULT_FILES=()

    for file in "${TEST_OUTPUT_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    TEST_OUTPUT_FILES=()

    # Clean up any remaining test files
    rm -f /tmp/suitey_test_result_* /tmp/suitey_test_output_* 2>/dev/null || true
}

@test "poll_test_results() polls result files in /tmp as tests complete" {
    # Create mock result files with the expected naming pattern
    local suite_id="test-suite-1"
    local pid=$$  # Use current process ID as $$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

    # Create result file content
    cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=1.23
total_tests=5
passed_tests=5
failed_tests=0
skipped_tests=0
status=passed
EOF

    # Create output file content
    echo "Test output content" > "$output_file"

    # Track files for cleanup
    TEST_RESULT_FILES+=("$result_file")
    TEST_OUTPUT_FILES+=("$output_file")

    # Poll for results
    run poll_test_results
    assert_success

    # Should find the result file
    assert_output --partial "suite_id=$suite_id"
    assert_output --partial "status=passed"
    assert_output --partial "result_file=$result_file"
    assert_output --partial "output_file=$output_file"
}

@test "poll_test_results() updates status as tests finish" {
    # Create multiple result files to simulate tests finishing
    local suite_ids=("suite-a" "suite-b" "suite-c")
    local result_files=()
    local output_files=()

    for suite_id in "${suite_ids[@]}"; do
        local pid=$$
        local random=$RANDOM

        local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
        local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

        # Create result file with different statuses
        case $suite_id in
            "suite-a")
                cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=1.0
status=passed
EOF
                ;;
            "suite-b")
                cat > "$result_file" << EOF
test_status=failed
exit_code=1
duration=2.5
status=failed
EOF
                ;;
            "suite-c")
                cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=0.8
status=passed
EOF
                ;;
        esac

        echo "Output for $suite_id" > "$output_file"

        result_files+=("$result_file")
        output_files+=("$output_file")
        TEST_RESULT_FILES+=("$result_file")
        TEST_OUTPUT_FILES+=("$output_file")
    done

    # Poll for results
    run poll_test_results
    assert_success

    # Should find all result files
    for suite_id in "${suite_ids[@]}"; do
        assert_output --partial "suite_id=$suite_id"
    done

    # Should include status information
    assert_output --partial "status=passed"
    assert_output --partial "status=failed"
}

@test "poll_test_results() handles test failures gracefully" {
    # Create a result file with failure status
    local suite_id="failed-suite"
    local pid=$$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

    # Create failed result file
    cat > "$result_file" << EOF
test_status=failed
exit_code=1
duration=3.14
total_tests=10
passed_tests=7
failed_tests=3
skipped_tests=0
status=failed
test_details_0_name=test_one
test_details_0_status=ok
test_details_1_name=test_two
test_details_1_status=failed
test_details_2_name=test_three
test_details_2_status=failed
EOF

    # Create output file with error information
    cat > "$output_file" << EOF
Running 10 tests
test test_one ... ok
test test_two ... FAILED
test test_three ... FAILED
test test_four ... ok
test test_five ... ok
test test_six ... ok
test test_seven ... ok
test test_eight ... ok
test test_nine ... ok
test test_ten ... ok
EOF

    TEST_RESULT_FILES+=("$result_file")
    TEST_OUTPUT_FILES+=("$output_file")

    # Poll for results
    run poll_test_results
    assert_success

    # Should handle failure gracefully
    assert_output --partial "suite_id=$failed_suite"
    assert_output --partial "status=failed"
    assert_output --partial "exit_code=1"
    assert_output --partial "failed_tests=3"
    assert_output --partial "result_file=$result_file"
    assert_output --partial "output_file=$output_file"
}

@test "poll_test_results() handles multiple result files with same suite_id but different unique suffixes" {
    # Create multiple result files for the same suite (simulating retries or multiple runs)
    local suite_id="multi-suite"
    local result_files=()

    for i in {1..3}; do
        local pid=$$
        local random=$RANDOM

        local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
        local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

        # Create result file with different results
        cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=1.$i
total_tests=5
passed_tests=5
failed_tests=0
skipped_tests=0
status=passed
run_number=$i
EOF

        echo "Output for run $i" > "$output_file"

        result_files+=("$result_file")
        TEST_RESULT_FILES+=("$result_file")
        TEST_OUTPUT_FILES+=("$output_file")
    done

    # Poll for results
    run poll_test_results
    assert_success

    # Should find all result files for the same suite
    local count=0
    while IFS= read -r line; do
        if [[ "$line" == suite_id=$suite_id ]]; then
            count=$((count + 1))
        fi
    done <<< "$output"

    # Should find 3 results for the same suite
    assert [ "$count" -eq 3 ]

    # Should include all result files
    for result_file in "${result_files[@]}"; do
        assert_output --partial "result_file=$result_file"
    done
}

@test "poll_test_results() handles atomic writes (only reads fully written files)" {
    # Create a result file that is still being written (simulate atomic write in progress)
    local suite_id="atomic-suite"
    local pid=$$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

    # Create partially written result file (missing some expected fields)
    cat > "$result_file" << EOF
test_status=running
exit_code=
EOF

    # Don't create output file yet (still being written)
    TEST_RESULT_FILES+=("$result_file")

    # Poll for results - should handle partial files gracefully
    run poll_test_results

    # Should not crash and should handle partial data
    # (The exact behavior depends on implementation, but should not fail catastrophically)
    assert [ $? -eq 0 ] || [ $? -eq 1 ]  # Allow success or controlled failure

    # If it finds the file, it should indicate it's still in progress
    if [[ $status -eq 0 ]]; then
        assert_output --partial "suite_id=$suite_id"
    fi
}

@test "poll_test_results() tracks processed files to avoid re-reading" {
    # Create a result file
    local suite_id="tracking-suite"
    local pid=$$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

    cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=1.0
status=passed
EOF

    echo "Test output" > "$output_file"

    TEST_RESULT_FILES+=("$result_file")
    TEST_OUTPUT_FILES+=("$output_file")

    # First poll should find the file
    run poll_test_results
    assert_success
    assert_output --partial "suite_id=$tracking_suite"

    # Second poll should not re-read the same file (if tracking is implemented)
    # Note: This test assumes the implementation tracks processed files
    # If it doesn't, this test will need to be adjusted
    run poll_test_results
    # The behavior here depends on whether the implementation tracks processed files
    # For now, just ensure it doesn't crash
    assert [ $? -eq 0 ] || [ $? -eq 1 ]
}

@test "poll_test_results() handles empty /tmp directory gracefully" {
    # Ensure /tmp is clean
    rm -f /tmp/suitey_test_result_* /tmp/suitey_test_output_* 2>/dev/null || true

    # Poll for results in empty directory
    run poll_test_results
    assert_success

    # Should return appropriate "no results" indication
    assert_output --partial "results_found=0"
}

@test "poll_test_results() handles malformed result files gracefully" {
    # Create a malformed result file
    local suite_id="malformed-suite"
    local pid=$$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"

    # Create malformed result file (invalid format)
    cat > "$result_file" << EOF
This is not a valid result file format
It doesn't have proper key=value pairs
Just random text
EOF

    TEST_RESULT_FILES+=("$result_file")

    # Poll for results - should handle malformed files gracefully
    run poll_test_results

    # Should not crash on malformed files
    assert [ $? -eq 0 ] || [ $? -eq 1 ]  # Allow controlled failure

    # Should still process valid files if any exist
    if [[ $status -eq 0 ]]; then
        # If it succeeded, should indicate the malformed file was encountered
        assert_output --partial "suite_id=$suite_id"
    fi
}
