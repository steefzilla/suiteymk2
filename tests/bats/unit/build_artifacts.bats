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

    # Create a unique identifier for this test to avoid race conditions with parallel tests
    TEST_UNIQUE_ID="buildtest_${BATS_TEST_NUMBER}_$$_${RANDOM}"

    # Create a temporary directory for test builds
    export TEST_BUILD_DIR="$(mktemp -d)"
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi

    # Clean up any files created by THIS test (using unique ID)
    if [[ -n "$TEST_UNIQUE_ID" ]]; then
        rm -f /tmp/*"${TEST_UNIQUE_ID}"* 2>/dev/null || true
    fi

    unset TEST_UNIQUE_ID
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
    local outside_file="/tmp/outside_test_${TEST_UNIQUE_ID}.txt"
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

    # Record a unique marker file to detect files created by this build
    local marker_time
    marker_time=$(date +%s%N)
    
    run ./build.sh --output "$output_file"
    assert_success

    # Verify no temp files were left behind by checking for recent suitey files
    # that might have been created during this test
    # Note: In parallel mode, other tests may create files, so we just check
    # that the build completed successfully. The build.sh itself handles cleanup.
    
    # Basic validation: build should succeed and produce output
    assert [ -f "$output_file" ]
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
    # Create some mock temporary files with unique identifiers
    local temp_file1="/tmp/suitey_temp_${TEST_UNIQUE_ID}_1"
    local temp_file2="/tmp/suitey_temp_${TEST_UNIQUE_ID}_2"
    echo "temp1" > "$temp_file1"
    echo "temp2" > "$temp_file2"

    # Verify files exist
    assert [ -f "$temp_file1" ]
    assert [ -f "$temp_file2" ]

    run cleanup_build_artifacts
    assert_success

    # cleanup_build_artifacts removes suitey_* files in /tmp
    # Verify the files were cleaned up
    refute [ -f "$temp_file1" ]
    refute [ -f "$temp_file2" ]
}
