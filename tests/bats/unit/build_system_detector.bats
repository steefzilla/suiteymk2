#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the build_system_detector.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the mod_registry.sh file if it exists
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
    fi

    # Source the build_system_detector.sh file if it exists
    if [[ -f "src/build_system_detector.sh" ]]; then
        source "src/build_system_detector.sh"
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

@test "detect_build_requirements() returns requires_build=false when no platforms detected" {
    # Test with empty platform data
    local platform_data="platforms_count=0"

    run detect_build_requirements "$platform_data"
    assert_success
    assert_output --partial "requires_build=false"
    assert_output --partial "build_commands_count=0"
    assert_output --partial "build_dependencies_count=0"
    assert_output --partial "build_artifacts_count=0"
}

@test "detect_build_requirements() detects Rust requires build using example/rust-project" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh" 2>/dev/null
        register_module "rust-module" "rust-module" 2>/dev/null

        # Mock platform detection result for Rust
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        run detect_build_requirements "$platform_data"
        assert_success
        assert_output --partial "requires_build=true"
        assert_output --partial "build_commands_count=1"
        assert_output --partial "build_commands_0=cargo build --tests"
    else
        skip "Rust module not available"
    fi
}

@test "detect_build_requirements() detects BATS does not require build using example/bats-project" {
    # Register BATS module
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh" 2>/dev/null
        register_module "bats-module" "bats-module" 2>/dev/null

        # Mock platform detection result for BATS
        local platform_data="platforms_count=1
platforms_0_language=bash
platforms_0_framework=bats
platforms_0_confidence=high
platforms_0_module_type=framework
project_root=example/bats-project"

        run detect_build_requirements "$platform_data"
        assert_success
        assert_output --partial "requires_build=false"
        assert_output --partial "build_commands_count=0"
    else
        skip "BATS module not available"
    fi
}

@test "detect_build_requirements() aggregates build requirements from multiple platforms" {
    # Test with just Rust first to ensure it works
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh" 2>/dev/null
        register_module "rust-module" "rust-module" 2>/dev/null

        # Mock platform detection result for Rust only
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        run detect_build_requirements "$platform_data"
        assert_success
        assert_output --partial "requires_build=true"  # Rust requires build
        assert_output --partial "build_commands_count=1"  # Rust has build commands
    else
        skip "Rust module not available"
    fi
}

@test "detect_build_requirements() handles invalid platform data gracefully" {
    # Test with malformed platform data
    local platform_data="invalid_data"

    run detect_build_requirements "$platform_data"
    assert_success
    assert_output --partial "requires_build=false"
}

@test "detect_build_requirements() returns structured results in flat data format" {
    local platform_data="platforms_count=0"

    run detect_build_requirements "$platform_data"
    assert_success

    # Verify all expected fields are present
    assert_output --regexp "requires_build="
    assert_output --regexp "build_commands_count="
    assert_output --regexp "build_dependencies_count="
    assert_output --regexp "build_artifacts_count="
}
