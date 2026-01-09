#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the mod_registry.sh and platform_detector.sh files for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the mod_registry.sh file if it exists
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
    fi

    # Source the platform_detector.sh file if it exists
    if [[ -f "src/platform_detector.sh" ]]; then
        source "src/platform_detector.sh"
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

@test "detect_platforms() detects Rust project with Cargo.toml" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Create a temporary directory with Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        
        # Run detect_platforms()
        run detect_platforms "$test_dir"
        assert_success
        
        # Should detect Rust platform
        assert_output --partial "platforms_count=1"
        assert_output --partial "platforms_0_language=rust"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() detects Bash/BATS project with .bats files" {
    # Register Bash module
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"
        
        # Create a temporary directory with .bats file
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test.bats"
        
        # Run detect_platforms()
        run detect_platforms "$test_dir"
        assert_success
        
        # Should detect Bash platform
        assert_output --partial "platforms_count=1"
        assert_output --partial "platforms_0_language=bash"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Bash module not found"
    fi
}

@test "detect_platforms() returns empty list for project with no detected platforms" {
    # Register modules
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Clean up functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done
        
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"
        
        # Create a temporary directory with no platform indicators
        local test_dir
        test_dir=$(mktemp -d)
        echo "some file" > "$test_dir/README.txt"
        
        # Run detect_platforms()
        run detect_platforms "$test_dir"
        assert_success
        
        # Should return platforms_count=0
        assert_output --partial "platforms_count=0"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Modules not found"
    fi
}

@test "detect_platforms() handles multiple platforms in same project" {
    # Register both modules
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Clean up functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done
        
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"
        
        # Create a temporary directory with both Rust and Bash indicators
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test.bats"
        
        # Run detect_platforms()
        run detect_platforms "$test_dir"
        assert_success
        
        # Should detect both platforms
        assert_output --partial "platforms_count=2"
        assert_output --partial "platforms_0_language=rust"
        assert_output --partial "platforms_1_language=bash"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Modules not found"
    fi
}

@test "detect_platforms() handles empty project root" {
    # Register modules
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Run detect_platforms() with empty directory
        local test_dir
        test_dir=$(mktemp -d)
        
        run detect_platforms "$test_dir"
        assert_success
        
        # Should handle gracefully (platforms_count=0)
        assert_output --partial "platforms_count=0"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() handles invalid project root" {
    # Register modules
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Run detect_platforms() with non-existent directory
        run detect_platforms "/nonexistent/directory"
        assert_success
        
        # Should handle gracefully (platforms_count=0)
        assert_output --partial "platforms_count=0"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() uses all registered modules" {
    # Register both modules
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Clean up functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done
        
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"
        
        # Create a temporary directory with only Rust indicators
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        
        # Run detect_platforms()
        run detect_platforms "$test_dir"
        assert_success
        
        # Should detect Rust but not Bash (no .bats files)
        assert_output --partial "platforms_count=1"
        assert_output --partial "platforms_0_language=rust"
        # Should not detect Bash
        refute_output --partial "platforms_1_language=bash"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Modules not found"
    fi
}

@test "detect_platforms() returns results in flat data format" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"
        
        # Create a temporary directory with Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        
        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")
        
        # Validate return format (should contain key=value pairs)
        run validate_module_return_format "$result"
        assert_success
        
        # Should contain key=value pairs
        assert echo "$result" | grep -q "="
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

