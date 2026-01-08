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
}

teardown() {
    # Clean up temporary build directory
    if [[ -n "$TEST_BUILD_DIR" && -d "$TEST_BUILD_DIR" ]]; then
        rm -rf "$TEST_BUILD_DIR"
    fi
}

@test "Integration: Full build process creates working suitey.sh executable" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Run the full build process
    run ./build.sh --output "$output_file"
    assert_success

    # Verify output file was created
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]

    # Verify it's a valid Bash script
    run bash -n "$output_file"
    assert_success

    # Verify it executes without errors
    run "$output_file" --version
    assert_success
    assert_output --partial "Suitey v"

    # Verify it shows help
    run "$output_file" --help
    assert_success
    assert_output --partial "Usage:"
}

@test "Integration: Built suitey.sh contains all source files" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Build the executable
    run ./build.sh --output "$output_file"
    assert_success

    # Verify environment.sh functions are included
    run grep -c "check_bash_version" "$output_file"
    assert_success
    assert [ "$output" -gt 0 ]

    run grep -c "check_docker_installed" "$output_file"
    assert_success
    assert [ "$output" -gt 0 ]

    run grep -c "check_docker_daemon_running" "$output_file"
    assert_success
    assert [ "$output" -gt 0 ]

    # Verify source file attribution is present
    run grep "Included from: src/environment.sh" "$output_file"
    assert_success
}

@test "Integration: Built suitey.sh contains all modules" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Build the executable
    run ./build.sh --output "$output_file"
    assert_success

    # Currently no modules exist, but the build should handle this gracefully
    # When modules are added, this test will verify they're included
    # For now, verify the build completes successfully even with no modules
    assert [ -f "$output_file" ]
    assert [ -x "$output_file" ]
}

@test "Integration: Build process respects filesystem isolation" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Track files created in project root (should not change)
    local project_root="$(pwd)"
    local project_files_before
    project_files_before=$(find "$project_root" -maxdepth 1 -type f -name "*.sh" 2>/dev/null | wc -l)

    # Run build process
    run ./build.sh --output "$output_file"
    assert_success

    # Verify output was created in temp directory (allowed location)
    assert [ -f "$output_file" ]

    # Verify no unexpected files were created in project root
    local project_files_after
    project_files_after=$(find "$project_root" -maxdepth 1 -type f -name "*.sh" 2>/dev/null | wc -l)

    # Project root should have same number of .sh files (only build.sh)
    # We're building to temp dir, so suitey.sh shouldn't be created in project root
    assert [ "$project_files_before" -eq "$project_files_after" ]

    # Verify output file is in /tmp (allowed location for filesystem isolation)
    # Get absolute path of output file's directory
    local output_dir="$(cd "$(dirname "$output_file")" && pwd)"
    assert [ "$output_dir" = "/tmp" ] || [ "${output_dir#/tmp/}" != "$output_dir" ]
}

@test "Integration: Built suitey.sh is self-contained" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Build the executable
    run ./build.sh --output "$output_file"
    assert_success

    # Verify it has shebang
    run head -n1 "$output_file"
    assert_output "#!/usr/bin/env bash"

    # Verify it has version information
    run grep "Version:" "$output_file"
    assert_success

    # Verify it has main function
    run grep "^main()" "$output_file"
    assert_success

    # Verify it calls main at the end
    run grep 'main "\$@"' "$output_file"
    assert_success
}

@test "Integration: Build process handles multiple source files" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Create a temporary source file for testing
    local test_source_file="src/test_source_$$.sh"
    cat > "$test_source_file" << 'EOF'
# Test source file
test_function() {
    echo "test function"
}
EOF

    # Build with the additional source file
    run ./build.sh --output "$output_file"
    assert_success

    # Verify the test source file is included
    run grep "test_function" "$output_file"
    assert_success

    # Clean up test source file
    rm -f "$test_source_file"
}

@test "Integration: Build process validates output correctly" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Build the executable
    run ./build.sh --output "$output_file"
    assert_success

    # Verify output validation occurred (check build output)
    run ./build.sh --verbose --output "$TEST_BUILD_DIR/validated.sh" 2>&1
    assert_success
    assert_output --partial "Build output validation completed successfully"
    assert_output --partial "Validated: syntax, executability, size, functions, execution, isolation"
}

@test "Integration: Build process cleans up temporary artifacts" {
    local output_file="$TEST_BUILD_DIR/suitey.sh"

    # Count temp files before build
    local temp_files_before
    temp_files_before=$(find /tmp -maxdepth 1 -name "suitey_*" 2>/dev/null | wc -l)

    # Run build
    run ./build.sh --output "$output_file"
    assert_success

    # Wait a moment for cleanup
    sleep 0.1

    # Count temp files after build
    local temp_files_after
    temp_files_after=$(find /tmp -maxdepth 1 -name "suitey_*" 2>/dev/null | wc -l)

    # Should have cleaned up (or at least not left more)
    assert [ "$temp_files_after" -le "$temp_files_before" ]
}
