#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    # Find the project root by going up from the test file location
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Create a temporary directory for test builds
    export TEST_BUILD_DIR="$(mktemp -d)"
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi
}

@test "--output option sets output path" {
    local output_file="$TEST_BUILD_DIR/custom_output.sh"

    run ./build.sh --output "$output_file"
    assert_success
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]
}

@test "--name option sets output name" {
    local output_file="$TEST_BUILD_DIR/my_custom_name.sh"

    run ./build.sh --name my_custom_name --output "$output_file"
    assert_success
    assert [ -f "$output_file" ]
}

@test "--version option includes version in bundle" {
    local output_file="$TEST_BUILD_DIR/versioned.sh"

    run ./build.sh --version 2.0.0 --output "$output_file"
    assert_success

    # Check that version is included in the bundle
    run grep "Version: 2.0.0" "$output_file"
    assert_success
}

@test "--clean option cleans output before build" {
    local output_file="$TEST_BUILD_DIR/clean_test.sh"

    # Create an existing file
    echo "old content" > "$output_file"
    chmod +x "$output_file"

    # Verify it exists
    assert [ -f "$output_file" ]

    # Build with --clean
    run ./build.sh --clean --output "$output_file"
    assert_success

    # Verify old content is gone and new content exists
    refute_output --partial "old content"
    assert [ -f "$output_file" ]
    run grep "Suitey" "$output_file"
    assert_success
}

@test "--verbose option shows detailed build output" {
    local output_file="$TEST_BUILD_DIR/verbose_test.sh"

    run ./build.sh --verbose --output "$output_file"
    assert_success

    # Check for verbose output indicators
    assert_output --partial "Starting Suitey build process"
    assert_output --partial "Discovering source files"
    assert_output --partial "Including"
}

@test "--help option shows help text" {
    run ./build.sh --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "--output"
    assert_output --partial "--help"
}

@test "--help shows all available options" {
    run ./build.sh --help
    assert_success
    assert_output --partial "--name"
    assert_output --partial "--version"
    assert_output --partial "--clean"
    assert_output --partial "--verbose"
}

@test "Multiple options can be combined" {
    local output_file="$TEST_BUILD_DIR/combined_test.sh"

    run ./build.sh --verbose --clean --version 3.0.0 --output "$output_file"
    assert_success
    assert [ -f "$output_file" ]

    # Verify version is included
    run grep "Version: 3.0.0" "$output_file"
    assert_success
}

@test "--clean without existing file still works" {
    local output_file="$TEST_BUILD_DIR/nonexistent.sh"

    # File doesn't exist
    refute [ -f "$output_file" ]

    # Build with --clean should still work
    run ./build.sh --clean --output "$output_file"
    assert_success
    assert [ -f "$output_file" ]
}
