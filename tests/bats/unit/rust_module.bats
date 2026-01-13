#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# Source the mod_registry.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the mod_registry.sh file if it exists
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
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

@test "Rust module can be registered" {
    # Source the Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Register the module
        register_module "rust-module" "rust-module"
        local register_status=$?
        assert_equal "$register_status" 0
        
        # Verify module is registered
        run get_module "rust-module"
        assert_success
        assert_output "rust-module"
    else
        skip "Rust module not found"
    fi
}

@test "Rust module implements detect() method" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Check that detect() exists
        run declare -f detect
        assert_success
        
        # Test detect() returns flat data format
        local test_dir
        test_dir=$(mktemp -d)
        run detect "$test_dir"
        assert_success
        
        # Should return flat data format
        assert_output --partial "detected="
        assert_output --partial "confidence="
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "Rust module detect() detects Cargo.toml" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Create a temporary directory with Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        
        # Run detect()
        local result
        result=$(detect "$test_dir")
        
        # Should detect Rust project
        assert echo "$result" | grep -q "detected=true"
        assert echo "$result" | grep -q "language=rust"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "Rust module detect() returns false when no Cargo.toml" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Create a temporary directory without Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        
        # Run detect()
        local result
        result=$(detect "$test_dir")
        
        # Should not detect Rust project
        assert echo "$result" | grep -q "detected=false"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "Rust module implements get_metadata() method" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Check that get_metadata() exists
        run declare -f get_metadata
        assert_success
        
        # Test get_metadata() returns flat data format
        run get_metadata
        assert_success
        
        # Should return flat data format with required fields
        assert_output --partial "language=rust"
        assert_output --partial "frameworks_"
        assert_output --partial "project_type="
        assert_output --partial "version="
    else
        skip "Rust module not found"
    fi
}

@test "Rust module get_metadata() includes Cargo framework" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include cargo framework
        assert echo "$metadata" | grep -q "frameworks_0=cargo" || echo "$metadata" | grep -q "cargo"
    else
        skip "Rust module not found"
    fi
}

@test "Rust module implements all required interface methods" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        # Validate interface
        run validate_module_interface
        assert_success
    else
        skip "Rust module not found"
    fi
}

@test "Rust module methods return flat data format" {
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        
        local test_dir
        test_dir=$(mktemp -d)
        
        # Test each method returns flat data format
        local result
        
        # detect()
        result=$(detect "$test_dir")
        run validate_module_return_format "$result"
        assert_success
        
        # check_binaries()
        result=$(check_binaries "$test_dir")
        run validate_module_return_format "$result"
        assert_success
        
        # discover_test_suites()
        result=$(discover_test_suites "$test_dir" "")
        run validate_module_return_format "$result"
        assert_success
        
        # detect_build_requirements()
        result=$(detect_build_requirements "$test_dir" "")
        run validate_module_return_format "$result"
        assert_success
        
        # get_build_steps()
        result=$(get_build_steps "$test_dir" "")
        run validate_module_return_format "$result"
        assert_success
        
        # get_metadata()
        result=$(get_metadata)
        run validate_module_return_format "$result"
        assert_success
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

