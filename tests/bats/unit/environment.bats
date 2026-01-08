#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Source the environment functions if they exist
    if [ -f src/environment.sh ]; then
        source src/environment.sh
    fi
}

@test "Bash version is 4.0 or higher" {
    run check_bash_version
    assert_success
}

@test "Docker is installed and accessible" {
    run check_docker_installed
    assert_success
}

@test "Docker daemon is running" {
    run check_docker_daemon_running
    assert_success
}

@test "Required directories exist (src/, tests/bats/, mod/)" {
    run check_required_directories
    assert_success
}

@test "/tmp directory is writable" {
    run check_tmp_writable
    assert_success
}

@test "Required test dependencies are available (BATS, bats-support, bats-assert)" {
    run check_test_dependencies
    assert_success
}
