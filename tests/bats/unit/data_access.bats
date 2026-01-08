#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the data_access.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the data_access.sh file if it exists
    if [[ -f "src/data_access.sh" ]]; then
        source "src/data_access.sh"
    fi
}

@test "data_get() extracts simple value from key=value format" {
    local data="name=suitey
version=0.1.0
framework=bats"

    run data_get "$data" "name"
    assert_success
    assert_output "suitey"

    run data_get "$data" "version"
    assert_success
    assert_output "0.1.0"

    run data_get "$data" "framework"
    assert_success
    assert_output "bats"
}

@test "data_get() returns empty string for missing key" {
    local data="name=suitey
version=0.1.0"

    run data_get "$data" "nonexistent"
    assert_success
    assert_output ""

    run data_get "$data" "missing_key"
    assert_success
    assert_output ""
}

@test "data_get() handles empty input (exit code 1)" {
    run data_get "" "key"
    assert_failure
    assert_equal "$status" 1

    run data_get "some=data" ""
    assert_failure
    assert_equal "$status" 1
}

@test "data_get() handles values with spaces" {
    local data="name=My Test Suite
description=This is a test suite"

    run data_get "$data" "name"
    assert_success
    assert_output "My Test Suite"

    run data_get "$data" "description"
    assert_success
    assert_output "This is a test suite"
}

@test "data_get() handles empty values" {
    local data="name=
version=0.1.0
empty_key="

    run data_get "$data" "name"
    assert_success
    assert_output ""

    run data_get "$data" "empty_key"
    assert_success
    assert_output ""
}

@test "data_get() removes surrounding quotes" {
    local data="name=\"quoted value\"
version='single quoted'"

    run data_get "$data" "name"
    assert_success
    assert_output "quoted value"

    run data_get "$data" "version"
    assert_success
    assert_output "single quoted"
}

@test "data_get() handles values with equals signs" {
    local data="command=echo hello=world
path=/usr/bin/env"

    run data_get "$data" "command"
    assert_success
    assert_output "echo hello=world"

    run data_get "$data" "path"
    assert_success
    assert_output "/usr/bin/env"
}

@test "data_get() returns first occurrence when key appears multiple times" {
    local data="key=first
other=value
key=second"

    run data_get "$data" "key"
    assert_success
    assert_output "first"
}

@test "data_get() handles boolean values" {
    local data="detected=true
enabled=false"

    run data_get "$data" "detected"
    assert_success
    assert_output "true"

    run data_get "$data" "enabled"
    assert_success
    assert_output "false"
}

@test "data_get() handles numeric values" {
    local data="count=42
duration=1.5
exit_code=0"

    run data_get "$data" "count"
    assert_success
    assert_output "42"

    run data_get "$data" "duration"
    assert_success
    assert_output "1.5"

    run data_get "$data" "exit_code"
    assert_success
    assert_output "0"
}

# Array Access Tests

@test "data_get_array() extracts array element by index" {
    local data="test_files_0=/path/to/test1.bats
test_files_1=/path/to/test2.bats
test_files_2=/path/to/test3.bats
test_files_count=3"

    run data_get_array "$data" "test_files" 0
    assert_success
    assert_output "/path/to/test1.bats"

    run data_get_array "$data" "test_files" 1
    assert_success
    assert_output "/path/to/test2.bats"

    run data_get_array "$data" "test_files" 2
    assert_success
    assert_output "/path/to/test3.bats"
}

@test "data_get_array() returns empty string for missing array element" {
    local data="test_files_0=/path/to/test1.bats
test_files_count=1"

    run data_get_array "$data" "test_files" 5
    assert_success
    assert_output ""
}

@test "data_get_array() handles invalid inputs (exit code 1)" {
    local data="test_files_0=/path/to/test1.bats
test_files_count=1"

    run data_get_array "" "test_files" 0
    assert_failure
    assert_equal "$status" 1

    run data_get_array "$data" "" 0
    assert_failure
    assert_equal "$status" 1

    # Non-numeric index should fail
    run data_get_array "$data" "test_files" "invalid"
    assert_failure
    assert_equal "$status" 1
}

@test "data_array_count() gets array count" {
    local data="indicators_0=file_extension
indicators_1=directory_pattern
indicators_2=config_file
indicators_count=3"

    run data_array_count "$data" "indicators"
    assert_success
    assert_output "3"
}

@test "data_array_count() returns 0 for missing array" {
    local data="other_key=value"

    run data_array_count "$data" "nonexistent"
    assert_success
    assert_output "0"
}

@test "data_array_count() returns 0 for non-numeric count" {
    local data="test_files_0=/path/to/test1.bats
test_files_count=invalid"

    run data_array_count "$data" "test_files"
    assert_success
    assert_output "0"
}

@test "data_array_count() handles empty input (exit code 1)" {
    run data_array_count "" "test_files"
    assert_failure
    assert_equal "$status" 1

    run data_array_count "some=data" ""
    assert_failure
    assert_equal "$status" 1
}

@test "data_get_array_all() gets all array elements" {
    local data="suites_0=unit
suites_1=integration
suites_2=e2e
suites_count=3"

    run data_get_array_all "$data" "suites"
    assert_success
    assert_output "unit
integration
e2e"
}

@test "data_get_array_all() returns empty for missing array" {
    local data="other_key=value"

    run data_get_array_all "$data" "nonexistent"
    assert_success
    assert_output ""
}

@test "data_get_array_all() returns empty for array with count 0" {
    local data="test_files_count=0"

    run data_get_array_all "$data" "test_files"
    assert_success
    assert_output ""
}

@test "data_get_array_all() handles empty input" {
    run data_get_array_all "" "test_files"
    assert_success
    assert_output ""

    run data_get_array_all "some=data" ""
    assert_success
    assert_output ""
}

@test "Array functions work with complex array names" {
    local data="test_suites_0=unit_tests
test_suites_1=integration_tests
test_suites_count=2"

    run data_get_array "$data" "test_suites" 0
    assert_success
    assert_output "unit_tests"

    run data_array_count "$data" "test_suites"
    assert_success
    assert_output "2"

    run data_get_array_all "$data" "test_suites"
    assert_success
    assert_output "unit_tests
integration_tests"
}
