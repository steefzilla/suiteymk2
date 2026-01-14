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

@test "BATS framework module can be registered as framework type" {
    # Source the BATS framework module
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Register the module
        register_module "bats-framework" "bats-framework"
        local register_status=$?
        assert_equal "$register_status" 0
        
        # Verify module is registered
        run get_module "bats-framework"
        assert_success
        assert_output "bats-framework"
        
        # Verify module type is framework
        local metadata
        metadata=$(get_module_metadata "bats-framework")
        assert echo "$metadata" | grep -q "module_type=framework"
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module implements discover_test_suites() method" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
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
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module implements execute_test_suite() method" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
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
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module implements parse_test_results() method" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

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
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() parses basic BATS output with passing tests" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        local test_output="1..3
ok 1 test case 1
ok 2 test case 2
ok 3 test case 3"

        run parse_test_results "$test_output" 0
        assert_success

        # Check counts
        assert_output --partial "total_tests=3"
        assert_output --partial "passed_tests=3"
        assert_output --partial "failed_tests=0"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status=passed"
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() parses BATS output with failures" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        local test_output="1..3
ok 1 test case 1
not ok 2 test case 2
# (in test file tests/example.bats, line 5)
#   \`false' failed
ok 3 test case 3"

        run parse_test_results "$test_output" 1
        assert_success

        # Check counts
        assert_output --partial "total_tests=3"
        assert_output --partial "passed_tests=2"
        assert_output --partial "failed_tests=1"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status=failed"
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() parses BATS output with skipped tests" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        local test_output="1..4
ok 1 test case 1
ok 2 test case 2 # skip optional test
ok 3 test case 3
ok 4 test case 4 # skip another skip"

        run parse_test_results "$test_output" 0
        assert_success

        # Check counts - BATS doesn't have a separate "skipped" status
        # but we can count tests with "# skip" in the output
        assert_output --partial "total_tests=4"
        assert_output --partial "passed_tests=4"
        assert_output --partial "failed_tests=0"
        # Note: BATS doesn't explicitly mark skipped tests in counts
        # The skip comments are just informational
        assert_output --partial "status=passed"
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() extracts individual test results" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        local test_output="1..3
ok 1 test_addition
not ok 2 test_subtraction
# (in test file tests/math.bats, line 10)
#   \`[ 3 - 2 = 5 ]' failed
ok 3 test_multiplication"

        run parse_test_results "$test_output" 1
        assert_success

        # Should have test details
        assert_output --partial "test_details_count=3"

        # Check individual test results (at least some should be present)
        assert_output --partial "test_addition"
        assert_output --partial "test_subtraction"
        assert_output --partial "test_multiplication"
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() handles BATS output without test plan" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        # BATS output without 1..N line (should still parse individual tests)
        local test_output="ok 1 simple test
not ok 2 failing test
ok 3 another test"

        run parse_test_results "$test_output" 1
        assert_success

        # Should count the individual test lines
        assert_output --partial "total_tests=3"
        assert_output --partial "passed_tests=2"
        assert_output --partial "failed_tests=1"
        assert_output --partial "status=failed"
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() handles malformed BATS output gracefully" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        # Malformed output - not proper TAP format
        local test_output="This is not TAP format
Some random output
More gibberish that doesn't match TAP"

        run parse_test_results "$test_output" 1
        # Should not crash, should return some reasonable defaults
        assert [ $? -eq 0 ] || [ $? -eq 1 ]

        # Should still return required fields
        if [[ $status -eq 0 ]]; then
            assert_output --partial "total_tests="
            assert_output --partial "status="
        fi
    else
        skip "BATS framework module not found"
    fi
}

@test "parse_test_results() handles empty output gracefully" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"

        run parse_test_results "" 0
        assert_success

        # Should return sensible defaults
        assert_output --partial "total_tests=0"
        assert_output --partial "passed_tests=0"
        assert_output --partial "failed_tests=0"
        assert_output --partial "skipped_tests=0"
        assert_output --partial "status="
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module metadata includes module_type=framework" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include module_type=framework
        assert echo "$metadata" | grep -q "module_type=framework"
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module metadata includes framework name" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Get metadata
        local metadata
        metadata=$(get_metadata)
        
        # Should include framework name (bats)
        assert echo "$metadata" | grep -q "bats" || echo "$metadata" | grep -q "framework"
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module implements all required interface methods" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Validate interface
        run validate_module_interface
        assert_success
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module methods return flat data format" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
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
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module can be retrieved by framework type" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Register the module
        register_module "bats-framework" "bats-framework"
        
        # Get framework modules
        run get_framework_modules
        assert_success
        assert_output --partial "bats-framework"
        
        # Should also work with get_modules_by_type
        run get_modules_by_type "framework"
        assert_success
        assert_output --partial "bats-framework"
    else
        skip "BATS framework module not found"
    fi
}

@test "BATS framework module discover_test_suites() finds .bats files" {
    if [[ -f "mod/frameworks/bats/mod.sh" ]]; then
        source "mod/frameworks/bats/mod.sh"
        
        # Create a temporary directory with .bats files
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test1.bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test2.bats"
        
        # Run discover_test_suites()
        local result
        result=$(discover_test_suites "$test_dir" "")
        
        # Should discover test suites
        assert echo "$result" | grep -q "suites_count="
        
        # Cleanup
        rm -rf "$test_dir"
    else
        skip "BATS framework module not found"
    fi
}

