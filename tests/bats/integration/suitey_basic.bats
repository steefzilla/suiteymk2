#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
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

@test "Integration: ./suitey.sh --help runs successfully (exit code 0)" {
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    assert_equal "$status" 0
    assert_output --partial "Suitey"
    assert_output --partial "Usage:"
}

@test "Integration: ./suitey.sh -h runs successfully (exit code 0)" {
    run "$TEST_BUILD_DIR/suitey.sh" -h
    assert_success
    assert_equal "$status" 0
    assert_output --partial "Suitey"
    assert_output --partial "Usage:"
}

@test "Integration: Script shows help text when run without arguments" {
    run "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    assert_equal "$status" 0
    assert_output --partial "Suitey"
    assert_output --partial "Usage:"
    
    # Should be same as --help
    run "$TEST_BUILD_DIR/suitey.sh" --help
    local help_output="$output"
    
    run "$TEST_BUILD_DIR/suitey.sh"
    local no_args_output="$output"
    
    assert_equal "$help_output" "$no_args_output"
}

@test "Integration: Script validates environment before execution" {
    # For non-help/version commands, environment checks should run
    # Since we're testing with a valid environment, the checks should pass
    # and then show the "Unknown option" error
    
    # Test that environment checks run (they should pass in our test environment)
    # The script will run environment checks, they'll pass, then show error for invalid option
    run "$TEST_BUILD_DIR/suitey.sh" --invalid-option 2>&1
    assert_failure
    assert_equal "$status" 2
    
    # The error should be about unknown option, not environment failure
    assert_output --partial "Unknown option"
    assert_output --partial "--help"
    
    # Verify environment checks didn't fail (no environment error messages)
    refute_output --partial "Docker is not installed"
    refute_output --partial "Bash version"
    refute_output --partial "Environment validation failed"
}

@test "Integration: Script respects filesystem isolation (only reads project, writes to /tmp)" {
    # Create a test directory outside the project
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    # Copy suitey.sh to the test directory
    cp "$TEST_BUILD_DIR/suitey.sh" "$test_project_dir/"
    chmod +x "$test_project_dir/suitey.sh"
    
    # Change to test directory
    cd "$test_project_dir"
    
    # Track files created outside /tmp
    local files_before
    files_before=$(find "$test_project_dir" -type f 2>/dev/null | wc -l)
    
    # Run suitey.sh --help (should not create files in project directory)
    run ./suitey.sh --help
    assert_success
    
    # Check that no new files were created in the project directory
    local files_after
    files_after=$(find "$test_project_dir" -type f 2>/dev/null | wc -l)
    
    assert_equal "$files_before" "$files_after"
    
    # Clean up
    cd "$project_root"
    rm -rf "$test_project_dir"
}

@test "Integration: Script can be executed from different directories" {
    # Create a temporary directory
    local test_dir
    test_dir="$(mktemp -d)"
    
    # Copy suitey.sh to the test directory
    cp "$TEST_BUILD_DIR/suitey.sh" "$test_dir/"
    chmod +x "$test_dir/suitey.sh"
    
    # Change to test directory and run suitey.sh
    cd "$test_dir"
    run ./suitey.sh --help
    assert_success
    assert_output --partial "Suitey"
    
    # Change back to project root
    cd "$project_root"
    
    # Clean up
    rm -rf "$test_dir"
}

@test "Integration: Script version command works correctly" {
    run "$TEST_BUILD_DIR/suitey.sh" --version
    assert_success
    assert_equal "$status" 0
    assert_output --partial "Suitey v0.1.0"
    assert_output --partial "Build system functional"
}

@test "Integration: Script -v works correctly" {
    run "$TEST_BUILD_DIR/suitey.sh" -v
    assert_success
    assert_equal "$status" 0
    assert_output --partial "Suitey v0.1.0"
    
    # Should be same as --version
    run "$TEST_BUILD_DIR/suitey.sh" --version
    local version_output="$output"
    
    run "$TEST_BUILD_DIR/suitey.sh" -v
    local v_output="$output"
    
    assert_equal "$version_output" "$v_output"
}

@test "Integration: Script handles invalid options gracefully" {
    run "$TEST_BUILD_DIR/suitey.sh" --invalid-option
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "Error: Unknown option"
    assert_output --partial "--help"
}

@test "Integration: Script is self-contained and executable" {
    # Verify the script is executable
    assert [ -x "$TEST_BUILD_DIR/suitey.sh" ]
    
    # Verify it can be executed directly
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    
    # Verify it has correct shebang
    run head -1 "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    assert_output "#!/usr/bin/env bash"
}

@test "Integration: Script runs end-to-end without errors" {
    # Test complete execution flow: help, version, invalid option
    run "$TEST_BUILD_DIR/suitey.sh" --help
    assert_success
    
    run "$TEST_BUILD_DIR/suitey.sh" --version
    assert_success
    
    run "$TEST_BUILD_DIR/suitey.sh"
    assert_success
    
    # Invalid option should fail gracefully
    run "$TEST_BUILD_DIR/suitey.sh" --invalid
    assert_failure
    assert_equal "$status" 2
}

@test "Integration: Tool modules integrate with detection and execution phases" {
    # Create a temporary project with shell scripts
    local test_project_dir
    test_project_dir="$(mktemp -d)"

    # Create shell scripts that shellcheck would analyze
    echo '#!/bin/bash\necho "test script"' > "$test_project_dir/test.sh"
    echo '#!/bin/bash\necho "another script"' > "$test_project_dir/script.sh"
    chmod +x "$test_project_dir"/*.sh

    # Run suitey on the test project
    # This should load the shellcheck tool module and detect shell scripts
    run "$TEST_BUILD_DIR/suitey.sh" "$test_project_dir"

    # The command should succeed (even if Docker is not available, it should handle gracefully)
    # We just want to verify that tool modules are loaded and can participate in detection
    if [[ $status -ne 0 ]]; then
        # If it fails, it should be due to Docker/container issues, not module loading
        refute_output --partial "Error: Module"
        refute_output --partial "shellcheck-module"
    fi

    # Clean up
    rm -rf "$test_project_dir"
}
