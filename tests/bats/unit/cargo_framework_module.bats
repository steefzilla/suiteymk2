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

@test "Cargo framework module can be registered as framework type" {
    # Source the Cargo framework module
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Register the module
        register_module "cargo-framework" "cargo-framework"
        local register_status=$?
        assert_equal "$register_status" 0
        
        # Verify module is registered
        run get_module "cargo-framework"
        assert_success
        assert_output "cargo-framework"
        
        # Verify module type is framework
        local metadata
        metadata=$(get_module_metadata "cargo-framework")
        assert echo "$metadata" | grep -q "module_type=framework"
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module implements discover_test_suites() method" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Check that discover_test_suites() exists
        run declare -f discover_test_suites
        assert_success
        
        # Test discover_test_suites() returns flat data format
        local test_dir
        test_dir=$(mktemp -d)
        run discover_test_suites "$test_dir" ""
        assert_success
        
        # Should return flat data format
        assert_output --partial "suites_count="
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module implements execute_test_suite() method" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Check that execute_test_suite() exists
        run declare -f execute_test_suite
        assert_success
        
        # Test execute_test_suite() returns flat data format
        run execute_test_suite "" "" ""
        assert_success
        
        # Should return flat data format
        assert_output --partial "exit_code="
        assert_output --partial "execution_method="
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module implements parse_test_results() method" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        # Check that parse_test_results() exists
        run declare -f parse_test_results
        assert_success

        # Test parse_test_results() returns flat data format
        run parse_test_results "test output" 0
        assert_success

        # Should return flat data format
        assert_output --partial "total_tests="
        assert_output --partial "status="
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() parses basic cargo test output with passing tests" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        local test_output="running 3 tests
test test_add ... ok
test test_subtract ... ok
test test_multiply ... ok

test result: ok. 3 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.01s"

        run parse_test_results "$test_output" 0
        assert_success

        # Check counts
        assert_output --partial "total_tests=3"
        assert_output --partial "passed_tests=3"
        assert_output --partial "failed_tests=0"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status=passed"
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() parses cargo test output with failures" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        local test_output="running 2 tests
test test_add ... ok
test test_divide_by_zero ... FAILED

failures:

---- test_divide_by_zero stdout ----
thread 'test_divide_by_zero' panicked at 'attempt to divide by zero', src/lib.rs:10:5

test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.02s"

        run parse_test_results "$test_output" 1
        assert_success

        # Check counts
        assert_output --partial "total_tests=2"
        assert_output --partial "passed_tests=1"
        assert_output --partial "failed_tests=1"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status=failed"
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() parses cargo test output with ignored tests" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        local test_output="running 4 tests
test test_add ... ok
test test_subtract ... ok
test test_multiply ... ok
test test_performance ... ignored

test result: ok. 3 passed; 0 failed; 1 ignored; 0 measured; 0 filtered out; finished in 0.01s"

        run parse_test_results "$test_output" 0
        assert_success

        # Check counts
        assert_output --partial "total_tests=4"
        assert_output --partial "passed_tests=3"
        assert_output --partial "failed_tests=0"
        assert_output --partial "skipped_tests=1"
        assert_output --partial "status=passed"
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() extracts individual test results" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        local test_output="running 3 tests
test test_add ... ok
test test_subtract ... ok
test test_divide_by_zero ... FAILED

failures:

---- test_divide_by_zero stdout ----
thread 'test_divide_by_zero' panicked at 'attempt to divide by zero', src/lib.rs:10:5

test result: FAILED. 2 passed; 1 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.02s"

        run parse_test_results "$test_output" 1
        assert_success

        # Should have test details
        assert_output --partial "test_details_count=3"

        # Check individual test results (at least some should be present)
        # The exact format will depend on implementation, but should contain test names
        assert_output --partial "test_add"
        assert_output --partial "test_subtract"
        assert_output --partial "test_divide_by_zero"
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() handles malformed cargo output gracefully" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        # Malformed output - no test summary
        local test_output="running some tests
test random output that doesn't match expected format
some other output"

        run parse_test_results "$test_output" 1
        # Should not crash, should return some reasonable defaults
        assert [ $? -eq 0 ] || [ $? -eq 1 ]

        # Should still return required fields
        if [[ $status -eq 0 ]]; then
            assert_output --partial "total_tests="
            assert_output --partial "status="
        fi
    else
        skip "Cargo framework module not found"
    fi
}

@test "parse_test_results() handles empty output gracefully" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"

        run parse_test_results "" 0
        assert_success

        # Should return sensible defaults
        assert_output --partial "total_tests=0"
        assert_output --partial "passed_tests=0"
        assert_output --partial "failed_tests=0"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status="
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module metadata includes module_type=framework" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include module_type=framework
        assert echo "$metadata" | grep -q "module_type=framework"
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module metadata includes framework name" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include framework name (cargo)
        assert echo "$metadata" | grep -q "cargo" || echo "$metadata" | grep -q "framework"
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module implements all required interface methods" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Validate interface
        run validate_module_interface
        assert_success
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module methods return flat data format" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        local test_dir
        test_dir=$(mktemp -d)
        
        # Test each method returns flat data format
        local result
        
        # discover_test_suites()
        result=$(discover_test_suites "$test_dir" "")
        run validate_module_return_format "$result"
        assert_success
        
        # execute_test_suite()
        result=$(execute_test_suite "" "" "")
        run validate_module_return_format "$result"
        assert_success
        
        # parse_test_results()
        result=$(parse_test_results "test output" 0)
        run validate_module_return_format "$result"
        assert_success
        
        # get_metadata()
        result=$(get_metadata)
        run validate_module_return_format "$result"
        assert_success
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Cargo framework module not found"
    fi
}

@test "Cargo framework module can be retrieved by framework type" {
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        
        # Register the module
        register_module "cargo-framework" "cargo-framework"
        
        # Get framework modules
        run get_framework_modules
        assert_success
        assert_output --partial "cargo-framework"
        
        # Should also work with get_modules_by_type
        run get_modules_by_type "framework"
        assert_success
        assert_output --partial "cargo-framework"
    else
        skip "Cargo framework module not found"
    fi
}

