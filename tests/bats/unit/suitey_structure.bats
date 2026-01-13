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

@test "Script sources src/environment.sh functions (bundled in)" {
    # Check that environment.sh functions are present in the bundled script
    run grep -q "check_bash_version" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    run grep -q "check_docker_installed" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    run grep -q "check_docker_daemon_running" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    run grep -q "check_required_directories" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    run grep -q "check_tmp_writable" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
}

@test "Script defines main function" {
    # Check that main function is defined
    run grep -q "^main() {" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    # Check that main function contains expected content
    local main_content
    main_content=$(grep -A 20 "^main() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    assert [ -n "$main_content" ]
    assert echo "$main_content" | grep -q "show_help"
}

@test "Script calls main function at end" {
    # Check that main is called at the end of the script
    local last_lines
    last_lines=$(tail -10 "$TEST_BUILD_DIR/suitey.sh")
    assert echo "$last_lines" | grep -q "main \"\$@\""
}

@test "Script runs environment checks before main execution" {
    # Check that run_environment_checks function exists
    run grep -q "^run_environment_checks() {" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    # Check that run_environment_checks calls the individual check functions
    local check_content
    check_content=$(grep -A 20 "^run_environment_checks() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    assert echo "$check_content" | grep -q "check_bash_version"
    assert echo "$check_content" | grep -q "check_docker_installed"
    assert echo "$check_content" | grep -q "check_docker_daemon_running"
    assert echo "$check_content" | grep -q "check_tmp_writable"
    
    # Check that main calls run_environment_checks (for non-help/version commands)
    local main_content
    main_content=$(grep -A 60 "^main() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    assert echo "$main_content" | grep -q "run_environment_checks"
}

@test "Script handles environment check failures gracefully" {
    # Check that run_environment_checks returns error code on failure
    local check_content
    check_content=$(grep -A 25 "^run_environment_checks() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    assert echo "$check_content" | grep -q "return 1"
    
    # Check that main handles environment check failures
    local main_content
    main_content=$(grep -A 60 "^main() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    assert echo "$main_content" | grep -q "EXIT_SUITEY_ERROR"
    assert echo "$main_content" | grep -q "Environment validation failed"
}

@test "Script skips environment checks for help/version commands" {
    # Check that help and version commands don't require environment checks
    # They should exit before running environment checks
    local main_content
    main_content=$(grep -A 40 "^main() {" "$TEST_BUILD_DIR/suitey.sh" || true)
    
    # Help command should exit before environment checks
    assert echo "$main_content" | grep -A 5 "show_help" | grep -q "exit"
    
    # Version command should exit before environment checks  
    assert echo "$main_content" | grep -A 5 "show_version" | grep -q "exit"
}

@test "Script has proper structure (shebang, header, functions, main)" {
    # Check shebang
    run head -1 "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    assert_output --partial "#!/usr/bin/env bash"
    
    # Check that it has a header comment
    run grep -q "Suitey - Cross-platform test runner" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    # Check that it has functions
    run grep -q "() {" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    # Check that it calls main
    run grep -q "main \"\$@\"" "$TEST_BUILD_DIR/suitey.sh"
    assert_success
}

@test "Environment functions are callable from script" {
    # Verify that we can source the script and call environment functions
    # This tests that the functions are properly included
    run bash -c "source '$TEST_BUILD_DIR/suitey.sh' && type check_bash_version >/dev/null 2>&1"
    assert_success
}

@test "Script structure is organized (functions before main)" {
    # Check that environment functions come before main function
    local main_line
    main_line=$(grep -n "^main() {" "$TEST_BUILD_DIR/suitey.sh" | cut -d: -f1)
    
    local env_line
    env_line=$(grep -n "^check_bash_version() {" "$TEST_BUILD_DIR/suitey.sh" | cut -d: -f1)
    
    # Environment functions should come before main
    assert [ "$env_line" -lt "$main_line" ]
}
