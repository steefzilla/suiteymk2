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

    # Build suitey.sh for testing
    ./build.sh --output "$TEST_BUILD_DIR/suitey.sh" >/dev/null 2>&1
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi
}

@test "Running ./suitey.sh --help exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
}

@test "Running ./suitey.sh -h exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" -h
    assert_success
}

@test "Help text contains 'Suitey' in output" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_output --partial "Suitey"
}

@test "Help text contains usage information" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_output --partial "Usage:"
}

@test "Help text contains available options" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_output --partial "--help"
    assert_output --partial "--version"
}

@test "Running ./suitey.sh (no args) shows help text" {
    run "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    assert_output --partial "Suitey"
    assert_output --partial "Usage:"
}

@test "Help text includes version information" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_output --partial "v"
}

@test "Help text is consistent between --help and -h" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    local help_output="$output"

    run "$TEST_BUILD_DIR/suitey.sh" -h
    local h_output="$output"

    assert_equal "$help_output" "$h_output"
}

@test "Help text is consistent between --help and no args" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    local help_output="$output"

    run "$TEST_BUILD_DIR/suitey.sh"
    local no_args_output="$output"

    assert_equal "$help_output" "$no_args_output"
}
