#!/usr/bin/env bats
# Advanced BATS test suite
# Demonstrates more complex testing scenarios

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "assert command output" {
    run echo "suitey bats test"
    assert_output "suitey bats test"
}

@test "assert success status" {
    run true
    assert_success
}

@test "assert failure status" {
    run false
    assert_failure
}

@test "conditional logic" {
    number=42
    if [ "$number" -gt 40 ]; then
        result="large"
    else
        result="small"
    fi
    [ "$result" = "large" ]
}

@test "array operations" {
    declare -a test_array=("suitey" "bats" "test")
    [ "${#test_array[@]}" -eq 3 ]
    [ "${test_array[0]}" = "suitey" ]
    [ "${test_array[1]}" = "bats" ]
    [ "${test_array[2]}" = "test" ]
}

