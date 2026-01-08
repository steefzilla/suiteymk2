#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Source the environment functions if they exist
    if [ -f src/environment.sh ]; then
        source src/environment.sh
    fi

    # Clean up any test files in /tmp
    rm -f "/tmp/suitey_test_file_$$"
    rm -rf "/tmp/suitey_test_dir_$$"
}

teardown() {
    # Clean up any test files in /tmp
    rm -f "/tmp/suitey_test_file_$$"
    rm -rf "/tmp/suitey_test_dir_$$"
}

@test "Can create files in /tmp directory" {
    run create_test_file_in_tmp
    assert_success
}

@test "Filesystem isolation principle is maintained" {
    run verify_filesystem_isolation_principle
    assert_success
}

@test "Temporary directories can be created in /tmp" {
    run create_test_directory_in_tmp
    assert_success
}

@test "Environment checks respect filesystem isolation principle" {
    run verify_environment_filesystem_isolation
    assert_success
}
