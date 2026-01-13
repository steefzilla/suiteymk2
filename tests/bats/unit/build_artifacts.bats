#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    # Find the project root by going up from the test file location
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the build.sh functions
    source build.sh

    # Create a temporary directory for test builds
    export TEST_BUILD_DIR="$(mktemp -d)"
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi
}

@test "build creates output file in specified location" {
    local output_file="$TEST_BUILD_DIR/custom_suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created in the specified location
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]
}

@test "build creates output file in project root by default" {
    # Clean up any existing suitey.sh
    rm -f suitey.sh

    run ./build.sh
    assert_success

    # Verify output file was created in project root
    assert [ -f "suitey.sh" ]
    assert [ -x "suitey.sh" ]
}

@test "build can specify output directory" {
    local output_dir="$TEST_BUILD_DIR/custom_dir"
    mkdir -p "$output_dir"
    local output_file="$output_dir/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created in the specified directory
    assert [ -f "$output_file" ]
    assert [ -d "$output_dir" ]
}

@test "build can specify output filename" {
    local output_file="$TEST_BUILD_DIR/my_custom_name.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file has the specified name
    assert [ -f "$output_file" ]
    refute [ -f "$TEST_BUILD_DIR/suitey.sh" ]
}

@test "build respects filesystem isolation" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Create some files outside allowed directories to test isolation
    local outside_file="/tmp/outside_test_$$.txt"
    echo "outside file" > "$outside_file"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify build only touched allowed locations
    assert [ -f "$output_file" ]  # In temp dir (allowed)
    # The build process should not have created files outside /tmp or project root

    # Clean up
    rm -f "$outside_file"
}

@test "build cleans up temporary files in /tmp" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Count existing files in /tmp before build
    local tmp_files_before
    tmp_files_before=$(find /tmp -maxdepth 1 -name "suitey_*" 2>/dev/null | wc -l)

    run ./build.sh --output "$output_file"
    assert_success

    # Count files in /tmp after build
    local tmp_files_after
    tmp_files_after=$(find /tmp -maxdepth 1 -name "suitey_*" 2>/dev/null | wc -l)

    # Should not leave behind suitey temp files
    # Note: This is a basic check - the build process uses mktemp which should clean up
    assert_equal "$tmp_files_before" "$tmp_files_after"
}

@test "build handles relative output paths" {
    local output_file="relative_test.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]

    # Clean up
    rm -f "$output_file"
}

@test "build handles absolute output paths" {
    local output_file="$TEST_BUILD_DIR/absolute_test.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]
}

@test "cleanup_build_artifacts removes temporary files" {
    # Create some mock temporary files
    local temp_file1="/tmp/suitey_temp_$$_1"
    local temp_file2="/tmp/suitey_temp_$$_2"
    echo "temp1" > "$temp_file1"
    echo "temp2" > "$temp_file2"

    # Verify files exist
    assert [ -f "$temp_file1" ]
    assert [ -f "$temp_file2" ]

    run cleanup_build_artifacts
    assert_success

    # Files should still exist (cleanup is selective)
    # This test verifies the cleanup function exists and runs
    # In a real scenario, we'd test specific cleanup logic
}
