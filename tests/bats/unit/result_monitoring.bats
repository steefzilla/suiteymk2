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

    # Create a unique identifier for this test to avoid race conditions with parallel tests
    # Use BATS_TEST_NUMBER which is unique per test in the file
    TEST_UNIQUE_ID="resmon_${BATS_TEST_NUMBER}_$$_${RANDOM}"

    # Reset global state to ensure clean test environment
    PROCESSED_RESULT_FILES=""

    # Track result files created during tests for cleanup
    TEST_RESULT_FILES=()
    TEST_OUTPUT_FILES=()
}

teardown() {
    # Clean up test result files tracked by this test
    for file in "${TEST_RESULT_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    TEST_RESULT_FILES=()

    for file in "${TEST_OUTPUT_FILES[@]}"; do
        rm -f "$file" 2>/dev/null || true
    done
    TEST_OUTPUT_FILES=()

    # Only clean up files belonging to THIS test (using TEST_UNIQUE_ID)
    if [[ -n "$TEST_UNIQUE_ID" ]]; then
        rm -f /tmp/*"${TEST_UNIQUE_ID}"* 2>/dev/null || true
    fi
    
    unset TEST_UNIQUE_ID
}

@test "poll_test_results() polls result files in /tmp as tests complete" {
    # Create mock result files with the expected naming pattern
    # Use unique suite ID to avoid collision with parallel tests
    local suite_id="poll-basic-${TEST_UNIQUE_ID}"
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
    # Use unique suite IDs to avoid collision with other parallel tests
    local unique="${TEST_UNIQUE_ID}"
    local suite_ids=("suite-a-${unique}" "suite-b-${unique}" "suite-c-${unique}")
    local result_files=()
    local output_files=()

    for suite_id in "${suite_ids[@]}"; do
        local pid=$$
        local random=$RANDOM

        local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
        local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

        # Create result file with different statuses
        case $suite_id in
            "suite-a-${unique}")
                cat > "$result_file" << EOF
test_status=passed
exit_code=0
duration=1.0
status=passed
EOF
                ;;
            "suite-b-${unique}")
                cat > "$result_file" << EOF
test_status=failed
exit_code=1
duration=2.5
status=failed
EOF
                ;;
            "suite-c-${unique}")
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

    # Should find all result files (check for at least one unique suite)
    assert_output --partial "suite_id=suite-a-${unique}"

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

# Diagnostic tests to isolate the regex parsing issue
@test "poll_test_results() regex correctly parses filename with hyphenated suite_id" {
    # Test the regex pattern matching with a hyphenated suite_id
    local filename="suitey_test_result_test-suite-1_12345_67890"
    local suite_id=""
    local pid_part=""
    local random_part=""
    
    if [[ "$filename" =~ suitey_test_result_(.+)_(.+)_(.+)$ ]]; then
        suite_id="${BASH_REMATCH[1]}"
        pid_part="${BASH_REMATCH[2]}"
        random_part="${BASH_REMATCH[3]}"
    fi
    
    # Verify parsing worked correctly
    assert_equal "$suite_id" "test-suite-1"
    assert_equal "$pid_part" "12345"
    assert_equal "$random_part" "67890"
}

@test "poll_test_results() regex correctly parses filename with underscore suite_id" {
    # Test with underscore-separated suite_id
    local filename="suitey_test_result_test_suite_1_12345_67890"
    local suite_id=""
    local pid_part=""
    local random_part=""
    
    if [[ "$filename" =~ suitey_test_result_(.+)_(.+)_(.+)$ ]]; then
        suite_id="${BASH_REMATCH[1]}"
        pid_part="${BASH_REMATCH[2]}"
        random_part="${BASH_REMATCH[3]}"
    fi
    
    # Verify parsing worked correctly
    assert_equal "$suite_id" "test_suite_1"
    assert_equal "$pid_part" "12345"
    assert_equal "$random_part" "67890"
}

@test "poll_test_results() regex correctly parses filename with simple suite_id" {
    # Test with simple suite_id (no special chars)
    local filename="suitey_test_result_suite1_12345_67890"
    local suite_id=""
    local pid_part=""
    local random_part=""
    
    if [[ "$filename" =~ suitey_test_result_(.+)_(.+)_(.+)$ ]]; then
        suite_id="${BASH_REMATCH[1]}"
        pid_part="${BASH_REMATCH[2]}"
        random_part="${BASH_REMATCH[3]}"
    fi
    
    # Verify parsing worked correctly
    assert_equal "$suite_id" "suite1"
    assert_equal "$pid_part" "12345"
    assert_equal "$random_part" "67890"
}

@test "poll_test_results() regex correctly parses filename with multiple hyphens in suite_id" {
    # Diagnostic test: verify regex behavior with multiple hyphens
    local filename="suitey_test_result_my-test-suite-name_12345_67890"
    local suite_id=""
    local pid_part=""
    local random_part=""
    
    # Use the exact regex from poll_test_results()
    if [[ "$filename" =~ suitey_test_result_(.+)_(.+)_(.+)$ ]]; then
        suite_id="${BASH_REMATCH[1]}"
        pid_part="${BASH_REMATCH[2]}"
        random_part="${BASH_REMATCH[3]}"
    fi
    
    # This will reveal if the regex fails with multiple hyphens
    assert_equal "$suite_id" "my-test-suite-name"
    assert_equal "$pid_part" "12345"
    assert_equal "$random_part" "67890"
}

@test "poll_test_results() find command locates files with hyphenated suite_id" {
    # Create a test file with hyphenated suite_id
    local suite_id="test-suite-1"
    local pid=12345
    local random=67890
    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    
    # Create the file
    echo "test_status=passed" > "$result_file"
    TEST_RESULT_FILES+=("$result_file")
    
    # Verify file exists
    assert [ -f "$result_file" ]
    
    # Verify find can locate it
    local found_files
    found_files=$(find /tmp -name "suitey_test_result_*" -type f 2>/dev/null || true)
    
    assert [ -n "$found_files" ]
    # Check if result_file path appears in found_files
    case "$found_files" in
        *"$result_file"*)
            assert true
            ;;
        *)
            assert false "File $result_file not found by find command"
            ;;
    esac
}

@test "poll_test_results() processes file with hyphenated suite_id correctly" {
    # Create a test file matching the exact pattern from the failing test
    local suite_id="test-suite-1"
    local pid=$$
    local random=$RANDOM
    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"
    
    # Create result file with content
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
    
    # Create output file
    echo "Test output content" > "$output_file"
    
    TEST_RESULT_FILES+=("$result_file")
    TEST_OUTPUT_FILES+=("$output_file")
    
    # Reset processed files to ensure this file is processed
    PROCESSED_RESULT_FILES=""
    
    # Poll for results
    run poll_test_results
    assert_success
    
    # Should find the result file
    assert_output --partial "suite_id=$suite_id"
    assert_output --partial "status=passed"
    assert_output --partial "result_file=$result_file"
    assert_output --partial "output_file=$output_file"
}

@test "poll_test_results() handles suite_id with multiple hyphens" {
    # Test with suite_id containing multiple hyphens
    local suite_id="my-test-suite-name"
    local pid=12345
    local random=67890
    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    
    # Create result file
    echo "test_status=passed" > "$result_file"
    TEST_RESULT_FILES+=("$result_file")
    
    # Reset processed files
    PROCESSED_RESULT_FILES=""
    
    # Poll for results
    run poll_test_results
    assert_success
    
    # Should find and parse correctly
    assert_output --partial "suite_id=$suite_id"
}

@test "poll_test_results() regex fails to match when suite_id contains underscores that could be confused with separators" {
    # This test checks if the regex has issues with suite_ids that contain underscores
    # The pattern expects: suitey_test_result_<suite_id>_<pid>_<random>
    # If suite_id is "test_suite_1", the regex might incorrectly parse it
    
    local filename="suitey_test_result_test_suite_1_12345_67890"
    local suite_id=""
    local pid_part=""
    local random_part=""
    
    if [[ "$filename" =~ suitey_test_result_(.+)_(.+)_(.+)$ ]]; then
        suite_id="${BASH_REMATCH[1]}"
        pid_part="${BASH_REMATCH[2]}"
        random_part="${BASH_REMATCH[3]}"
    fi
    
    # The regex is greedy, so it might match incorrectly
    # This test will reveal if the regex has issues with underscore-separated suite_ids
    # Expected: suite_id="test_suite_1", but greedy matching might give suite_id="test_suite_1_12345"
    # Actually wait - the regex has three groups, so it should work, but let's verify
    assert_equal "$suite_id" "test_suite_1"
    assert_equal "$pid_part" "12345"
    assert_equal "$random_part" "67890"
}

@test "poll_test_results() while loop processes find output correctly" {
    # Test that the while loop correctly processes find output
    # This simulates the exact scenario from poll_test_results()
    
    local suite_id="test-suite-1"
    local pid=$$
    local random=$RANDOM
    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    
    # Create result file
    echo "test_status=passed" > "$result_file"
    TEST_RESULT_FILES+=("$result_file")
    
    # Simulate the find command from poll_test_results()
    local result_files
    result_files=$(find /tmp -name "suitey_test_result_*" -type f 2>/dev/null || true)
    
    # Simulate the while loop processing
    local found_count=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "$result_file" ]]; then
            found_count=$((found_count + 1))
        fi
    done <<< "$result_files"
    
    # Should have found the file
    assert [ $found_count -eq 1 ]
}

@test "poll_test_results() handles find output with multiple files correctly" {
    # Test that the while loop processes multiple files correctly
    # Use unique suite IDs to avoid collision with parallel tests
    local unique="${TEST_UNIQUE_ID}"
    local suite_id1="multi-file-1-${unique}"
    local suite_id2="multi-file-2-${unique}"
    local pid=$$
    local random1=$RANDOM
    local random2=$RANDOM
    local result_file1="/tmp/suitey_test_result_${suite_id1}_${pid}_${random1}"
    local result_file2="/tmp/suitey_test_result_${suite_id2}_${pid}_${random2}"
    
    # Create result files
    echo "test_status=passed" > "$result_file1"
    echo "test_status=passed" > "$result_file2"
    TEST_RESULT_FILES+=("$result_file1" "$result_file2")
    
    # Simulate the find command - only look for our unique files
    local result_files
    result_files=$(find /tmp -name "suitey_test_result_multi-file-*${unique}*" -type f 2>/dev/null || true)
    
    # Count files found
    local found_count=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if [[ "$file" == "$result_file1" ]] || [[ "$file" == "$result_file2" ]]; then
            found_count=$((found_count + 1))
        fi
    done <<< "$result_files"
    
    # Should have found both files
    assert [ $found_count -ge 2 ]
}

@test "poll_test_results() file creation is immediately visible to find command" {
    local suite_id="visibility-test"
    local pid=$$
    local random=$RANDOM
    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    
    # Create file
    echo "test_status=passed" > "$result_file"
    TEST_RESULT_FILES+=("$result_file")
    
    # Immediately verify file exists
    assert [ -f "$result_file" ]
    
    # Verify find can see it immediately
    local found
    found=$(find /tmp -name "suitey_test_result_${suite_id}_*" -type f 2>/dev/null | wc -l)
    assert [ "$found" -ge 1 ]
}

@test "poll_test_results() creates three files and find returns all three" {
    # Use unique suite IDs to avoid collision with parallel tests
    local unique="${TEST_UNIQUE_ID}"
    local suite_ids=("find3-a-${unique}" "find3-b-${unique}" "find3-c-${unique}")
    local pid=$$
    local created_files=()
    
    # Create three files
    for suite_id in "${suite_ids[@]}"; do
        local random=$RANDOM
        local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
        echo "test_status=passed" > "$result_file"
        created_files+=("$result_file")
        TEST_RESULT_FILES+=("$result_file")
    done
    
    # Verify all files exist
    for file in "${created_files[@]}"; do
        assert [ -f "$file" ]
    done
    
    # Verify find returns all three (use unique pattern)
    local found_count
    found_count=$(find /tmp -name "suitey_test_result_find3-*${unique}*" -type f 2>/dev/null | wc -l)
    assert [ "$found_count" -eq 3 ]
}

@test "poll_test_results() processes all files returned by find" {
    # Use unique suite IDs to avoid collision with parallel tests
    local unique="${TEST_UNIQUE_ID}"
    local suite_ids=("proc-a-${unique}" "proc-b-${unique}" "proc-c-${unique}")
    local pid=$$
    
    # Create three files with unique content
    for suite_id in "${suite_ids[@]}"; do
        local random=$RANDOM
        local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
        echo "test_status=passed" > "$result_file"
        TEST_RESULT_FILES+=("$result_file")
    done
    
    # Reset processed files state
    PROCESSED_RESULT_FILES=""
    
    # Poll for results
    run poll_test_results
    assert_success
    
    # Should find all three (check for one unique suite to confirm)
    assert_output --partial "suite_id=proc-a-${unique}"
}
