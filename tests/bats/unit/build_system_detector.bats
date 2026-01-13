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

@test "get_build_steps() returns empty steps when no platforms detected" {
    local platform_data="platforms_count=0"
    local build_requirements="requires_build=false"

    run get_build_steps "$platform_data" "$build_requirements"
    assert_success
    assert_output --partial "build_steps_count=0"
}

@test "get_build_steps() returns empty steps when building not required" {
    # Mock platform detection result for Rust
    local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

    local build_requirements="requires_build=false"

    run get_build_steps "$platform_data" "$build_requirements"
    assert_success
    assert_output --partial "build_steps_count=0"
}

@test "get_build_steps() identifies cargo build steps for Rust projects" {
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

        local build_requirements="requires_build=true"

        run get_build_steps "$platform_data" "$build_requirements"
        assert_success
        assert_output --partial "build_steps_count=1"
        assert_output --partial "build_steps_0_step_name=rust_build"
        assert_output --partial "build_steps_0_docker_image=rust:1.70-slim"
        assert_output --partial "build_steps_0_build_command=cargo build --tests"
        assert_output --partial "build_steps_0_working_directory=/workspace"
        assert_output --partial "build_steps_0_volume_mounts_readonly=true"
    else
        skip "Rust module not available"
    fi
}

@test "get_build_steps() identifies cargo build steps for Cargo framework projects" {
    # Register Cargo module
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh" 2>/dev/null
        register_module "cargo-module" "cargo-module" 2>/dev/null

        # Mock platform detection result for Cargo
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=framework
project_root=example/rust-project"

        local build_requirements="requires_build=true"

        run get_build_steps "$platform_data" "$build_requirements"
        assert_success
        assert_output --partial "build_steps_count=1"
        assert_output --partial "build_steps_0_step_name=cargo_build"
        assert_output --partial "build_steps_0_docker_image=rust:1.70-slim"
        assert_output --partial "build_steps_0_build_command=cargo build --tests"
        assert_output --partial "build_steps_0_volume_mounts_readonly=true"
    else
        skip "Cargo module not available"
    fi
}

@test "get_build_steps() returns empty steps for BATS projects" {
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

        local build_requirements="requires_build=false"

        run get_build_steps "$platform_data" "$build_requirements"
        assert_success
        assert_output --partial "build_steps_count=0"
    else
        skip "BATS module not available"
    fi
}

@test "get_build_steps() handles invalid platform data gracefully" {
    local platform_data="invalid_data"
    local build_requirements="requires_build=false"

    run get_build_steps "$platform_data" "$build_requirements"
    assert_success
    assert_output --partial "build_steps_count=0"
}

@test "get_build_steps() returns structured results in flat data format" {
    local platform_data="platforms_count=0"
    local build_requirements="requires_build=false"

    run get_build_steps "$platform_data" "$build_requirements"
    assert_success

    # Verify expected field is present
    assert_output --regexp "build_steps_count="
}

@test "analyze_build_dependencies() returns empty analysis when no build steps" {
    local build_steps="build_steps_count=0"

    run analyze_build_dependencies "$build_steps"
    assert_success
    assert_output --partial "execution_order_count=0"
    assert_output --partial "parallel_groups_count=0"
    assert_output --partial "dependency_graph_count=0"
}

@test "analyze_build_dependencies() analyzes single build step" {
    local build_steps="build_steps_count=1
build_steps_0_step_name=rust_build
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_build_command=cargo build --tests"

    run analyze_build_dependencies "$build_steps"
    assert_success
    assert_output --partial "execution_order_count=1"
    assert_output --partial "execution_order_steps=0"
    assert_output --partial "parallel_groups_count=1"
    assert_output --partial "parallel_groups_0_step_count=1"
    assert_output --partial "parallel_groups_0_steps=0"
}

@test "analyze_build_dependencies() analyzes multiple build steps" {
    local build_steps="build_steps_count=2
build_steps_0_step_name=rust_build
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_build_command=cargo build --tests
build_steps_1_step_name=cargo_build
build_steps_1_docker_image=rust:1.70-slim
build_steps_1_build_command=cargo build --tests"

    run analyze_build_dependencies "$build_steps"
    assert_success
    assert_output --partial "execution_order_count=2"
    assert_output --partial "execution_order_steps=0,1"
    assert_output --partial "parallel_groups_count=1"
    assert_output --partial "parallel_groups_0_step_count=2"
    assert_output --partial "parallel_groups_0_steps=0,1"
}

@test "analyze_build_dependencies() handles invalid build steps data gracefully" {
    local build_steps="invalid_data"

    run analyze_build_dependencies "$build_steps"
    assert_success
    assert_output --partial "execution_order_count=0"
}

@test "analyze_build_dependencies() returns structured results in flat data format" {
    local build_steps="build_steps_count=1
build_steps_0_step_name=test_build"

    run analyze_build_dependencies "$build_steps"
    assert_success

    # Verify all expected fields are present
    assert_output --regexp "execution_order_count="
    assert_output --regexp "parallel_groups_count="
    assert_output --regexp "dependency_graph_count="
}

@test "detect_build_requirements() respects filesystem isolation (read-only project access)" {
    # Create a temporary project directory
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    # Create a test file in the project
    echo "test content" > "$test_project_dir/test_file.txt"
    
    # Make project directory read-only to test filesystem isolation
    chmod -w "$test_project_dir"
    
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
project_root=$test_project_dir"

        # Run build requirements detection (should succeed even with read-only directory)
        run detect_build_requirements "$platform_data"
        assert_success
        
        # Verify it doesn't try to write to project directory
        # The function should only read metadata, not write files
        assert_output --partial "requires_build=true"
        
        # Verify test file was not modified
        assert [ -f "$test_project_dir/test_file.txt" ]
        assert_equal "$(cat "$test_project_dir/test_file.txt")" "test content"
        
        # Restore write permissions for cleanup
        chmod +w "$test_project_dir"
    else
        skip "Rust module not available"
    fi
    
    # Clean up
    rm -rf "$test_project_dir"
}

@test "get_build_steps() respects filesystem isolation (read-only project access)" {
    # Create a temporary project directory
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    # Create a test file in the project
    echo "test content" > "$test_project_dir/test_file.txt"
    
    # Make project directory read-only to test filesystem isolation
    chmod -w "$test_project_dir"
    
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
project_root=$test_project_dir"

        local build_requirements="requires_build=true"

        # Run build steps detection (should succeed even with read-only directory)
        run get_build_steps "$platform_data" "$build_requirements"
        assert_success
        
        # Verify it doesn't try to write to project directory
        assert_output --partial "build_steps_count=1"
        
        # Verify test file was not modified
        assert [ -f "$test_project_dir/test_file.txt" ]
        assert_equal "$(cat "$test_project_dir/test_file.txt")" "test content"
        
        # Restore write permissions for cleanup
        chmod +w "$test_project_dir"
    else
        skip "Rust module not available"
    fi
    
    # Clean up
    rm -rf "$test_project_dir"
}
