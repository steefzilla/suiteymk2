#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

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

@test "./suitey.sh --help exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_equal "$status" 0
}

@test "./suitey.sh -h exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" -h
    assert_success
    assert_equal "$status" 0
}

@test "./suitey.sh --version exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" --version
    assert_success
    assert_equal "$status" 0
}

@test "./suitey.sh -v exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" -v
    assert_success
    assert_equal "$status" 0
}

@test "./suitey.sh (no args) exits with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    assert_equal "$status" 0
}

@test "./suitey.sh --invalid-option exits with code 2" {
    run "$TEST_BUILD_DIR/suitey.sh" --invalid-option
    assert_failure
    assert_equal "$status" 2
}

@test "./suitey.sh --unknown exits with code 2" {
    run "$TEST_BUILD_DIR/suitey.sh" --unknown
    assert_failure
    assert_equal "$status" 2
}

@test "./suitey.sh -x exits with code 2" {
    run "$TEST_BUILD_DIR/suitey.sh" -x
    assert_failure
    assert_equal "$status" 2
}

@test "Invalid option shows error message" {
    run "$TEST_BUILD_DIR/suitey.sh" --invalid-option
    assert_failure
    assert_output --partial "Error: Unknown option"
    assert_output --partial "--help"
}

@test "Script handles errors gracefully" {
    # Test that invalid options don't cause script crashes
    run "$TEST_BUILD_DIR/suitey.sh" --invalid-option
    assert_failure
    assert_equal "$status" 2
    # Should output error message, not crash
    assert_output --partial "Error"
}

@test "Help options consistently exit with code 0" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    local help_status="$status"
    
    run "$TEST_BUILD_DIR/suitey.sh" -h
    local h_status="$status"
    
    run "$TEST_BUILD_DIR/suitey.sh"
    local no_args_status="$status"
    
    assert_equal "$help_status" 0
    assert_equal "$h_status" 0
    assert_equal "$no_args_status" 0
}
