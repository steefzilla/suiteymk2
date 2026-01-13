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

@test "Bash module can be registered" {
    # Source the Bash module
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Register the module
        register_module "bash-module" "bash-module"
        local register_status=$?
        assert_equal "$register_status" 0
        
        # Verify module is registered
        run get_module "bash-module"
        assert_success
        assert_output "bash-module"
    else
        skip "Bash module not found"
    fi
}

@test "Bash module implements detect() method" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
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
        skip "Bash module not found"
    fi
}

@test "Bash module detect() detects .bats files" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Create a temporary directory with .bats file
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test.bats"
        
        # Run detect()
        local result
        result=$(detect "$test_dir")
        
        # Should detect Bash/BATS project
        assert echo "$result" | grep -q "detected=true"
        assert echo "$result" | grep -q "language=bash"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Bash module not found"
    fi
}

@test "Bash module detect() detects .sh files" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Create a temporary directory with .sh file
        local test_dir
        test_dir=$(mktemp -d)
        echo "#!/usr/bin/env bash" > "$test_dir/script.sh"
        
        # Run detect()
        local result
        result=$(detect "$test_dir")
        
        # Should detect Bash project (may be low confidence)
        assert echo "$result" | grep -q "detected=true"
        assert echo "$result" | grep -q "language=bash"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Bash module not found"
    fi
}

@test "Bash module detect() returns false when no indicators" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Create a temporary directory without Bash indicators
        local test_dir
        test_dir=$(mktemp -d)
        
        # Run detect()
        local result
        result=$(detect "$test_dir")
        
        # Should not detect Bash project
        assert echo "$result" | grep -q "detected=false"
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Bash module not found"
    fi
}

@test "Bash module implements get_metadata() method" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Check that get_metadata() exists
        run declare -f get_metadata
        assert_success
        
        # Test get_metadata() returns flat data format
        run get_metadata
        assert_success
        
        # Should return flat data format with required fields
        assert_output --partial "language=bash"
        assert_output --partial "frameworks_"
        assert_output --partial "project_type="
        assert_output --partial "version="
    else
        skip "Bash module not found"
    fi
}

@test "Bash module get_metadata() includes BATS framework" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include bats framework
        assert echo "$metadata" | grep -q "frameworks_0=bats" || echo "$metadata" | grep -q "bats"
    else
        skip "Bash module not found"
    fi
}

@test "Bash module implements all required interface methods" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
        # Validate interface
        run validate_module_interface
        assert_success
    else
        skip "Bash module not found"
    fi
}

@test "Bash module methods return flat data format" {
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        
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
        skip "Bash module not found"
    fi
}

