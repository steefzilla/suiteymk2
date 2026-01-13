#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
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

@test "Integration: build.sh creates functional suitey.sh by default" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Run build.sh with custom output to temp directory
    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]

    # Verify output file has expected content
    run "$output_file" --help
    assert_success
    assert_output --partial "Suitey v"
    assert_output --partial "Usage:"
}

@test "Integration: build.sh creates specified output file" {
    local custom_output="$TEST_BUILD_DIR/test_output.sh"

    # Run build.sh with custom output
    run ./build.sh --output "$custom_output"
    assert_success

    # Verify custom output file was created
    assert [ -f "$custom_output" ]
    assert [ -x "$custom_output" ]

    # Verify it has expected content
    run "$custom_output" --help
    assert_success
    assert_output --partial "Suitey v"
}

@test "Integration: generated suitey.sh contains version information" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    # Check that the generated file contains version metadata
    run grep "Version:" "$output_file"
    assert_success
    assert_output --partial "Version:"

    run grep "Built:" "$output_file"
    assert_success
    assert_output --partial "Built:"
}

@test "Integration: generated suitey.sh has correct shebang" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success

    run head -n1 "$output_file"
    assert_output "#!/usr/bin/env bash"
}

@test "Integration: build.sh output shows build progress" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    run ./build.sh --output "$output_file"
    assert_success
    assert_output --partial "Starting Suitey build process"
    assert_output --partial "Build completed successfully"
    assert_output --partial "Output: $output_file"
}

@test "Integration: build.sh overwrites existing file safely" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Create initial file
    echo "#!/bin/bash" > "$output_file"
    echo "echo 'old version'" >> "$output_file"
    chmod +x "$output_file"

    # Verify initial file works
    run "$output_file"
    assert_output "old version"

    # Build new version
    run ./build.sh --output "$output_file"
    assert_success

    # Verify new file was created and old content is gone
    run "$output_file" --help
    assert_success
    refute_output "old version"
    assert_output --partial "Suitey v"
}
