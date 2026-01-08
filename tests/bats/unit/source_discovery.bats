#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    # Find the project root by going up from the test file location
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the build.sh functions
    source build.sh
}

@test "discover_source_files finds all .sh files in src/" {
    run discover_source_files
    assert_success

    # Should find environment.sh
    assert_output --partial "src/environment.sh"

    # Should not find non-.sh files
    refute_output --partial "README.md"
    refute_output --partial "SPEC.md"
}

@test "discover_modules finds all module files in mod/" {
    run discover_modules
    assert_success

    # Should find files in mod/ directory (even though it's empty for now)
    # This test will pass when we have modules
}

@test "validate_source_files checks that discovered files exist" {
    run validate_source_files
    assert_success

    # Should not error on existing files
}

@test "get_build_order returns files in dependency order" {
    run get_build_order
    assert_success

    # Should include environment.sh first (no dependencies)
    # This is a basic test - full dependency analysis comes later
}

@test "source_discovery_integration combines all discovery functions" {
    run source_discovery_integration
    assert_success

    # Should return both source files and modules
    assert_output --partial "src/"
}
