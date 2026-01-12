#!/usr/bin/env bats
# BATS test suite for basic functionality
# This is an example project for testing Suitey's BATS detection capabilities

setup() {
    # Setup runs before each test
    export TEST_VAR="suitey_test"
}

teardown() {
    # Cleanup after each test
    unset TEST_VAR
}

@test "basic arithmetic addition" {
    result=$((2 + 3))
    [ "$result" -eq 5 ]
}

@test "string comparison" {
    [ "$TEST_VAR" = "suitey_test" ]
}

@test "command execution" {
    run echo "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "file operations" {
    temp_file="/tmp/suitey_test_$$.txt"
    echo "test content" > "$temp_file"
    [ -f "$temp_file" ]
    run cat "$temp_file"
    [ "$output" = "test content" ]
    rm -f "$temp_file"
}

