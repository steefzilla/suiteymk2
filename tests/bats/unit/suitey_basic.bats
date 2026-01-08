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

@test "suitey.sh file exists after build" {
    assert [ -f "$TEST_BUILD_DIR/suitey.sh" ]
}

@test "suitey.sh is executable" {
    assert [ -x "$TEST_BUILD_DIR/suitey.sh" ]
}

@test "suitey.sh has correct shebang" {
    run head -n1 "$TEST_BUILD_DIR/suitey.sh"
    assert_output "#!/usr/bin/env bash"
}

@test "suitey.sh can be executed without errors" {
    run "$TEST_BUILD_DIR/suitey.sh" --version
    assert_success
    assert_output --partial "Suitey v"
}

@test "suitey.sh has valid Bash syntax" {
    run bash -n "$TEST_BUILD_DIR/suitey.sh"
    assert_success
}

@test "suitey.sh has reasonable file size" {
    local file_size
    file_size=$(wc -c < "$TEST_BUILD_DIR/suitey.sh")
    assert [ "$file_size" -gt 1000 ]  # Should be substantial (contains bundled source)
}

@test "suitey.sh contains version information" {
    run grep "Version:" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
}

@test "suitey.sh contains main function" {
    run grep "^main()" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
}
