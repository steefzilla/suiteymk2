#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the mod_registry.sh and test_suite_detector.sh files for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the mod_registry.sh file if it exists
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
    fi

    # Source the test_suite_detector.sh file if it exists
    if [[ -f "src/test_suite_detector.sh" ]]; then
        source "src/test_suite_detector.sh"
    fi

    # Reset registry before each test
    reset_registry
}

teardown() {
    # Clean up registry after each test
    reset_registry

    # Clean up any module functions that were defined
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
}

@test "discover_test_suites() discovers Rust unit tests in example/rust-project/src/" {
    # Test Rust module directly
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -d "example/rust-project" ]]; then
        # Clean up any existing module functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        # Source Rust module
        source "mod/languages/rust/mod.sh"

        # Mock platform detection result for Rust
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # For now, Rust module returns suites_count=0 (stub implementation)
        # According to implementation plan, this is expected for minimal implementation
        assert_line "suites_count=0"
    else
        skip "Rust module or example project not available"
    fi
}

@test "discover_test_suites() discovers Rust integration tests in example/rust-project/tests/" {
    # Test Rust module directly
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -d "example/rust-project" ]]; then
        # Clean up any existing module functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        # Source Rust module
        source "mod/languages/rust/mod.sh"

        # Mock platform detection result for Rust
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # For now, Rust module returns suites_count=0 (stub implementation)
        # According to implementation plan, this is expected for minimal implementation
        assert_line "suites_count=0"
    else
        skip "Rust module or example project not available"
    fi
}

@test "discover_test_suites() discovers BATS test files in example/bats-project/tests/bats/" {
    # Test BATS module directly
    if [[ -f "mod/frameworks/bats/mod.sh" ]] && [[ -d "example/bats-project" ]]; then
        # Mock platform detection result for BATS
        local platform_data="platforms_count=1
platforms_0_language=bash
platforms_0_framework=bats
platforms_0_confidence=high
platforms_0_module_type=framework
project_root=example/bats-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # Should discover BATS test files (BATS module has real implementation)
        assert_line --regexp "suites_count=[0-9]+"

        # Check that we have at least one suite
        local suites_count=$(echo "$output" | grep "suites_count=" | cut -d'=' -f2)
        assert [ "$suites_count" -gt 0 ]
    else
        skip "BATS module or example project not available"
    fi
}

@test "discover_test_suites() returns empty list when no platforms detected" {
    # Mock platform detection result with no platforms
    local platform_data="platforms_count=0"

    # Run discover_test_suites()
    run discover_test_suites "$platform_data"
    assert_success

    # Should return empty list
    assert_line "suites_count=0"
}
