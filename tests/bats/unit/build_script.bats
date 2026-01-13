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

@test "build.sh file exists" {
    assert [ -f "build.sh" ]
}

@test "build.sh is executable" {
    assert [ -x "build.sh" ]
}

@test "Build script has shebang" {
    run head -n1 build.sh
    assert_output "#!/usr/bin/env bash"
}

@test "Running ./build.sh --help shows help text" {
    run ./build.sh --help
    assert_success
    assert_output --partial "Usage:"
}

@test "Running ./build.sh without args builds suitey.sh" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]

    # Verify the generated file is functional
    run "$output_file" --help
    assert_success
    assert_output --partial "Suitey v"
}

@test "Running ./build.sh -h shows help text" {
    run ./build.sh -h
    assert_success
    assert_output --partial "Usage:"
}

@test "Running ./build.sh --invalid-option exits with error" {
    run ./build.sh --invalid-option
    assert_failure
    assert_output --partial "Run './build.sh --help' for usage information"
}

@test "Generated suitey.sh has correct shebang" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    run head -n1 "$output_file"
    assert_output "#!/usr/bin/env bash"
}

@test "Generated suitey.sh contains build metadata" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    run grep "Version:" "$output_file"
    assert_success

    run grep "Built:" "$output_file"
    assert_success
}
