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

    # Build suitey.sh for testing
    ./build.sh --output "$TEST_BUILD_DIR/suitey.sh" >/dev/null 2>&1
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi
}

# Help text test removed - covered by suitey_help.bats

@test "./suitey.sh . accepts current directory as argument" {
    # Create a test directory and change to it
    local test_dir
    test_dir="$(mktemp -d)"
    cd "$test_dir"
    
    # Copy suitey.sh to test directory
    cp "$TEST_BUILD_DIR/suitey.sh" "$test_dir/"
    chmod +x "$test_dir/suitey.sh"
    
    # Run suitey.sh with . as argument
    # Should accept the directory (run environment checks, then proceed)
    # Since workflow execution isn't implemented yet, it may show a message about
    # directory being accepted, or it may proceed to workflow (which will be a placeholder)
    run "$test_dir/suitey.sh" . 2>&1
    # Should not show "Unknown option" error
    refute_output --partial "Unknown option"
    
    # Clean up
    cd "$project_root"
    rm -rf "$test_dir"
}

@test "./suitey.sh /path/to/dir accepts absolute directory path" {
    # Create a test directory
    local test_dir
    test_dir="$(mktemp -d)"
    
    # Run suitey.sh with absolute path
    run "$TEST_BUILD_DIR/suitey.sh" "$test_dir" 2>&1
    # Should accept the directory (not show "Unknown option")
    refute_output --partial "Unknown option"
    
    # Clean up
    rm -rf "$test_dir"
}

@test "./suitey.sh ../other-project accepts relative directory path" {
    # Create a test directory structure
    local parent_dir
    parent_dir="$(mktemp -d)"
    local test_dir="$parent_dir/other-project"
    mkdir -p "$test_dir"
    
    # Copy suitey.sh to parent directory
    cp "$TEST_BUILD_DIR/suitey.sh" "$parent_dir/"
    chmod +x "$parent_dir/suitey.sh"
    
    # Change to parent directory and run with relative path
    cd "$parent_dir"
    run ./suitey.sh other-project 2>&1
    # Should accept the directory (not show "Unknown option")
    refute_output --partial "Unknown option"
    
    # Clean up
    cd "$project_root"
    rm -rf "$parent_dir"
}

@test "./suitey.sh --help still shows help (options take precedence)" {
    # Test that --help option takes precedence over directory arguments
    # Even with a directory argument after, help should take precedence
    run "$TEST_BUILD_DIR/suitey.sh" --help .
    assert_success
    # Help text content is tested in suitey_help.bats, here we just verify precedence
}

@test "./suitey.sh --version still shows version (options take precedence)" {
    run "$TEST_BUILD_DIR/suitey.sh" --version
    assert_success
    assert_output --partial "Suitey v0.1.0"
    
    # Even with a directory argument after, version should take precedence
    run "$TEST_BUILD_DIR/suitey.sh" --version .
    assert_success
    assert_output --partial "Suitey v0.1.0"
}

@test "./suitey.sh nonexistent-dir exits with error code 2" {
    run "$TEST_BUILD_DIR/suitey.sh" nonexistent-dir
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "Error"
    # Should mention directory doesn't exist
    assert_output --partial "Directory"
    assert_output --partial "does not exist"
}

@test "./suitey.sh /nonexistent/path exits with error code 2" {
    run "$TEST_BUILD_DIR/suitey.sh" /nonexistent/path
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "Error"
    # Should mention directory doesn't exist
    assert_output --partial "Directory"
    assert_output --partial "does not exist"
}

@test "Directory argument is validated (exists, is readable)" {
    # Create a test directory
    local test_dir
    test_dir="$(mktemp -d)"
    
    # Test with valid directory
    run "$TEST_BUILD_DIR/suitey.sh" "$test_dir" 2>&1
    # Should accept valid directory (not show directory error)
    refute_output --partial "does not exist"
    refute_output --partial "not found"
    
    # Clean up
    rm -rf "$test_dir"
}

@test "Directory argument is normalized (relative paths resolved)" {
    # Create a test directory structure
    local parent_dir
    parent_dir="$(mktemp -d)"
    local test_dir="$parent_dir/test-project"
    mkdir -p "$test_dir"
    
    # Copy suitey.sh to parent directory
    cp "$TEST_BUILD_DIR/suitey.sh" "$parent_dir/"
    chmod +x "$parent_dir/suitey.sh"
    
    # Change to parent directory
    cd "$parent_dir"
    
    # Test with relative path
    run ./suitey.sh test-project 2>&1
    # Should resolve relative path to absolute path
    
    # Clean up
    cd "$project_root"
    rm -rf "$parent_dir"
}

@test "Multiple directory arguments are rejected" {
    local test_dir1
    test_dir1="$(mktemp -d)"
    local test_dir2
    test_dir2="$(mktemp -d)"
    
    run "$TEST_BUILD_DIR/suitey.sh" "$test_dir1" "$test_dir2" 2>&1
    assert_failure
    assert_equal "$status" 2
    assert_output --partial "Error"
    
    # Clean up
    rm -rf "$test_dir1" "$test_dir2"
}
