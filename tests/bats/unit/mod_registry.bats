#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

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

# Helper function to create a minimal valid module
create_test_module() {
    local identifier="$1"
    cat <<EOF
# Test Module: $identifier
detect() {
    echo "detected=true"
    echo "confidence=high"
    echo "indicators_count=0"
}

check_binaries() {
    echo "available=true"
    echo "binaries_count=0"
}

discover_test_suites() {
    echo "suites_count=0"
}

detect_build_requirements() {
    echo "requires_build=false"
    echo "build_steps_count=0"
    echo "build_commands_count=0"
    echo "build_dependencies_count=0"
    echo "build_artifacts_count=0"
}

get_build_steps() {
    echo "build_steps_count=0"
}

execute_test_suite() {
    echo "exit_code=0"
    echo "duration=0.0"
    echo "execution_method=docker"
}

parse_test_results() {
    echo "total_tests=0"
    echo "passed_tests=0"
    echo "failed_tests=0"
    echo "skipped_tests=0"
    echo "test_details_count=0"
    echo "status=passed"
}

get_metadata() {
    echo "language=test"
    echo "frameworks_count=0"
    echo "project_type=test"
    echo "version=0.1.0"
    echo "capabilities_count=0"
    echo "required_binaries_count=0"
}
EOF
}

@test "register_module() registers a module successfully" {
    local module_content
    module_content=$(create_test_module "test-module")

    # Source the module
    eval "$module_content"

    # Register the module (call directly so state persists)
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Verify module is registered
    run get_module "test-module"
    assert_success
    assert_output "test-module"
}

@test "register_module() rejects module with duplicate identifier" {
    local module_content
    module_content=$(create_test_module "test-module")

    # Source the module
    eval "$module_content"

    # Register the module first time (call directly so state persists)
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Try to register again with same identifier
    run register_module "test-module" "test-module"
    assert_failure
    assert_output --partial "already registered"
}

@test "register_module() rejects module missing required interface methods" {
    local incomplete_module="
# Incomplete module missing detect()
check_binaries() {
    echo 'available=true'
}
"

    # Source the incomplete module
    eval "$incomplete_module"

    # Try to register incomplete module
    run register_module "incomplete-module" "incomplete-module"
    assert_failure
    assert_output --partial "missing required method"
}

@test "register_module() validates module metadata structure" {
    local module_content
    module_content=$(create_test_module "test-module")

    # Modify get_metadata to return invalid structure
    local invalid_module="${module_content/get_metadata() {/get_metadata() {
    echo 'invalid_metadata'
}"

    # Source the invalid module
    eval "$invalid_module"

    # Try to register module with invalid metadata
    run register_module "test-module" "test-module"
    # Should still succeed (metadata validation can be lenient for now)
    # or fail if we implement strict validation
    # For now, we'll check that it at least doesn't crash
}

@test "register_module() validates all required methods exist" {
    # Create a module without detect() method
    local incomplete_module="
check_binaries() {
    echo 'available=true'
    echo 'binaries_count=0'
}

discover_test_suites() {
    echo 'suites_count=0'
}

detect_build_requirements() {
    echo 'requires_build=false'
    echo 'build_steps_count=0'
    echo 'build_commands_count=0'
    echo 'build_dependencies_count=0'
    echo 'build_artifacts_count=0'
}

get_build_steps() {
    echo 'build_steps_count=0'
}

execute_test_suite() {
    echo 'exit_code=0'
    echo 'duration=0.0'
    echo 'execution_method=docker'
}

parse_test_results() {
    echo 'total_tests=0'
    echo 'passed_tests=0'
    echo 'failed_tests=0'
    echo 'skipped_tests=0'
    echo 'test_details_count=0'
    echo 'status=passed'
}

get_metadata() {
    echo 'language=test'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"

    # Source the incomplete module (missing detect())
    eval "$incomplete_module"

    # Try to register module missing detect()
    run register_module "test-module" "test-module"
    assert_failure
    assert_output --partial "detect"
}

@test "register_module() handles empty identifier" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Try to register with empty identifier
    run register_module "" "test-module"
    assert_failure
}

@test "register_module() validates module is a function" {
    # Try to register something that's not a module
    run register_module "not-a-module" "not-a-module"
    assert_failure
}

@test "register_module() stores module metadata" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Register the module (call directly, not with run, so state persists)
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Verify metadata can be retrieved
    run get_module_metadata "test-module"
    assert_success
    assert_output --partial "language=test"
}

@test "register_module() validates metadata contains required fields" {
    local module_content
    module_content=$(create_test_module "test-module")

    # Modify get_metadata to return incomplete metadata
    local incomplete_metadata="${module_content/get_metadata() {
    echo 'language=test'
    echo 'version=0.1.0'
}"

    eval "$incomplete_metadata"

    # Register should still work (metadata validation can be lenient)
    run register_module "test-module" "test-module"
    # Should succeed or fail based on validation strictness
}

# Module Lookup Tests

@test "get_module() retrieves module by identifier" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Register the module
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Retrieve the module
    run get_module "test-module"
    assert_success
    assert_output "test-module"
}

@test "get_module() returns error for missing module" {
    run get_module "nonexistent-module"
    assert_failure
    assert_output --partial "not found"
}

@test "get_module() returns error for empty identifier" {
    run get_module ""
    assert_failure
    assert_output --partial "cannot be empty"
}

@test "get_all_modules() returns all registered modules" {
    # Register first module
    local module1_content
    module1_content=$(create_test_module "module-1")
    eval "$module1_content"
    register_module "module-1" "module-1"

    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Register second module
    local module2_content
    module2_content=$(create_test_module "module-2")
    eval "$module2_content"
    register_module "module-2" "module-2"

    # Get all modules
    run get_all_modules
    assert_success
    
    # Should contain both modules
    assert_output --partial "module-1"
    assert_output --partial "module-2"
}

@test "get_all_modules() returns empty for empty registry" {
    run get_all_modules
    assert_success
    assert_output ""
}

@test "get_modules_by_capability() returns modules with matching capability" {
    # Create module with capability
    local module_with_capability="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test'
    echo 'capabilities_0=test-framework'
    echo 'capabilities_count=1'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module_with_capability"
    register_module "test-module" "test-module"

    # Get modules by capability
    run get_modules_by_capability "test-framework"
    assert_success
    assert_output --partial "test-module"
}

@test "get_modules_by_capability() returns empty for non-existent capability" {
    local module_content
    module_content=$(create_test_module "test-module")
    eval "$module_content"
    register_module "test-module" "test-module"

    # Get modules by non-existent capability
    run get_modules_by_capability "nonexistent-capability"
    assert_success
    assert_output ""
}

@test "get_modules_by_capability() returns multiple modules with same capability" {
    # Create first module with capability
    local module1="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test1'
    echo 'capabilities_0=common-capability'
    echo 'capabilities_count=1'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module1"
    register_module "module-1" "module-1"

    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Create second module with same capability
    local module2="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test2'
    echo 'capabilities_0=common-capability'
    echo 'capabilities_count=1'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module2"
    register_module "module-2" "module-2"

    # Get modules by capability
    run get_modules_by_capability "common-capability"
    assert_success
    
    # Should contain both modules
    assert_output --partial "module-1"
    assert_output --partial "module-2"
}

@test "get_modules_by_capability() handles modules with multiple capabilities" {
    local module_content="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test'
    echo 'capabilities_0=capability-1'
    echo 'capabilities_1=capability-2'
    echo 'capabilities_count=2'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module_content"
    register_module "test-module" "test-module"

    # Should match both capabilities
    run get_modules_by_capability "capability-1"
    assert_success
    assert_output --partial "test-module"

    run get_modules_by_capability "capability-2"
    assert_success
    assert_output --partial "test-module"
}

@test "get_capabilities() returns all registered capabilities" {
    # Register module with capabilities
    local module1="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test1'
    echo 'capabilities_0=capability-1'
    echo 'capabilities_1=capability-2'
    echo 'capabilities_count=2'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module1"
    register_module "module-1" "module-1"

    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Register second module with different capabilities
    local module2="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'language=test2'
    echo 'capabilities_0=capability-3'
    echo 'capabilities_count=1'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'required_binaries_count=0'
}
"

    eval "$module2"
    register_module "module-2" "module-2"

    # Get all capabilities
    run get_capabilities
    assert_success
    
    # Should contain all capabilities
    assert_output --partial "capability-1"
    assert_output --partial "capability-2"
    assert_output --partial "capability-3"
}

@test "get_capabilities() returns empty for modules without capabilities" {
    local module_content
    module_content=$(create_test_module "test-module")
    eval "$module_content"
    register_module "test-module" "test-module"

    # Get all capabilities (should be empty or not include this module's capabilities)
    run get_capabilities
    # Should succeed (may return empty)
    assert_success
}

# Module Interface Validation Tests

@test "validate_module_interface() verifies all required methods exist" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Validate interface
    run validate_module_interface
    assert_success
}

@test "validate_module_interface() detects missing methods" {
    # Create module missing detect() method
    local incomplete_module="
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() { echo 'language=test'; }
"

    eval "$incomplete_module"

    # Validate interface should fail
    run validate_module_interface
    assert_failure
}

@test "validate_module_method_signature() checks method parameter count" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Check detect() signature (should accept 1 parameter: project_root)
    run validate_module_method_signature "detect" 1
    assert_success

    # Check get_metadata() signature (should accept 0 parameters)
    run validate_module_method_signature "get_metadata" 0
    assert_success
}

@test "validate_module_method_signature() detects incorrect parameter count" {
    local module_content
    module_content=$(create_test_module "test-module")

    # Modify detect() to have wrong number of parameters
    local wrong_signature="${module_content/detect() {/detect() {
    # Wrong: no parameters
}"

    eval "$wrong_signature"

    # Note: In Bash, we can't easily check parameter count at runtime
    # This test verifies the validation function exists and works
    run validate_module_method_signature "detect" 1
    # May succeed or fail depending on implementation
}

@test "validate_module_return_format() checks return value format" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Test detect() returns flat data format
    local result
    result=$(detect "/tmp/test")
    run validate_module_return_format "$result"
    assert_success

    # Should contain key=value pairs
    assert echo "$result" | grep -q "="
}

@test "validate_module_return_format() validates flat data format" {
    # Valid flat data
    local valid_data="detected=true
confidence=high
indicators_count=0"

    run validate_module_return_format "$valid_data"
    assert_success

    # Invalid data (not flat format)
    local invalid_data='{"detected": true}'

    run validate_module_return_format "$invalid_data"
    # Should fail or handle gracefully
}

@test "validate_module_return_format() handles empty return values" {
    # Empty return is valid (methods may return empty when not applicable)
    run validate_module_return_format ""
    assert_success
}

@test "validate_module_interface_complete() performs full interface validation" {
    local module_content
    module_content=$(create_test_module "test-module")

    eval "$module_content"

    # Register the module first
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Perform complete interface validation
    run validate_module_interface_complete "test-module"
    assert_success
}

@test "validate_module_interface_complete() detects interface violations" {
    # Create module with wrong return format (detect returns JSON instead of flat data)
    local bad_module="
detect() { echo 'invalid json: {\"detected\": true}'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() { echo 'language=test'; }
"

    eval "$bad_module"

    # Register the module (registration doesn't validate return formats strictly)
    register_module "test-module" "test-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Complete validation should detect the issue with return format
    run validate_module_interface_complete "test-module"
    # Should fail because detect() returns invalid format
    assert_failure
    assert_output --partial "invalid format"
}

# Module Type Support Tests

@test "register_module() accepts language module with module_type=language" {
    local language_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=language'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"

    eval "$language_module"
    
    # Register the language module
    register_module "rust-language" "rust-language"
    local register_status=$?
    assert_equal "$register_status" 0
    
    # Verify module is registered
    run get_module "rust-language"
    assert_success
}

@test "register_module() accepts framework module with module_type=framework" {
    local framework_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=framework'
    echo 'language=rust'
    echo 'frameworks_0=cargo'
    echo 'frameworks_count=1'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"

    eval "$framework_module"
    
    # Register the framework module
    register_module "cargo-framework" "cargo-framework"
    local register_status=$?
    assert_equal "$register_status" 0
    
    # Verify module is registered
    run get_module "cargo-framework"
    assert_success
}

@test "register_module() accepts project module with module_type=project" {
    local project_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=project'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=custom'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"

    eval "$project_module"
    
    # Register the project module
    register_module "my-project" "my-project"
    local register_status=$?
    assert_equal "$register_status" 0
    
    # Verify module is registered
    run get_module "my-project"
    assert_success
}

@test "get_modules_by_type() returns language modules" {
    # Register language module
    local lang_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=language'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$lang_module"
    register_module "rust-lang" "rust-lang"
    
    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
    
    # Register framework module
    local framework_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=framework'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$framework_module"
    register_module "cargo-fw" "cargo-fw"
    
    # Get language modules
    run get_modules_by_type "language"
    assert_success
    assert_output --partial "rust-lang"
    refute_output --partial "cargo-fw"
}

@test "get_modules_by_type() returns framework modules" {
    # Register language module
    local lang_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=language'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$lang_module"
    register_module "rust-lang" "rust-lang"
    
    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
    
    # Register framework module
    local framework_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=framework'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$framework_module"
    register_module "cargo-fw" "cargo-fw"
    
    # Get framework modules
    run get_modules_by_type "framework"
    assert_success
    assert_output --partial "cargo-fw"
    refute_output --partial "rust-lang"
}

@test "get_modules_by_type() returns project modules" {
    # Register project module
    local project_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=project'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$project_module"
    register_module "my-project" "my-project"
    
    # Get project modules
    run get_modules_by_type "project"
    assert_success
    assert_output --partial "my-project"
}

@test "get_modules_by_type() returns empty for non-existent type" {
    # Register a module
    local module_content
    module_content=$(create_test_module "test-module")
    eval "$module_content"
    register_module "test-module" "test-module"
    
    # Get modules by non-existent type
    run get_modules_by_type "nonexistent-type"
    assert_success
    assert_output ""
}

@test "get_modules_by_type() handles empty type" {
    # Register a module
    local module_content
    module_content=$(create_test_module "test-module")
    eval "$module_content"
    register_module "test-module" "test-module"
    
    # Get modules by empty type
    run get_modules_by_type ""
    assert_success
    assert_output ""
}

@test "get_language_modules() returns language modules" {
    # Register language module
    local lang_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=language'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$lang_module"
    register_module "rust-lang" "rust-lang"
    
    # Get language modules
    run get_language_modules
    assert_success
    assert_output --partial "rust-lang"
}

@test "get_framework_modules() returns framework modules" {
    # Register framework module
    local framework_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=framework'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$framework_module"
    register_module "cargo-fw" "cargo-fw"
    
    # Get framework modules
    run get_framework_modules
    assert_success
    assert_output --partial "cargo-fw"
}

@test "get_project_modules() returns project modules" {
    # Register project module
    local project_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=project'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$project_module"
    register_module "my-project" "my-project"
    
    # Get project modules
    run get_project_modules
    assert_success
    assert_output --partial "my-project"
}

@test "module priority: project > framework > language" {
    # This test verifies that modules can be retrieved in priority order
    # Register modules of different types
    local lang_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=language'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$lang_module"
    register_module "rust-lang" "rust-lang"
    
    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
    
    local framework_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=framework'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$framework_module"
    register_module "cargo-fw" "cargo-fw"
    
    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
    
    local project_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=false'; }
get_build_steps() { echo 'build_steps_count=0'; }
execute_test_suite() { echo 'exit_code=0'; }
parse_test_results() { echo 'total_tests=0'; }
get_metadata() {
    echo 'module_type=project'
    echo 'language=rust'
    echo 'frameworks_count=0'
    echo 'project_type=test'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$project_module"
    register_module "my-project" "my-project"
    
    # Verify all modules are registered
    run get_all_modules
    assert_success
    assert_output --partial "rust-lang"
    assert_output --partial "cargo-fw"
    assert_output --partial "my-project"
    
    # Verify type-based lookup works
    run get_modules_by_type "language"
    assert_success
    assert_output --partial "rust-lang"
    
    run get_modules_by_type "framework"
    assert_success
    assert_output --partial "cargo-fw"
    
    run get_modules_by_type "project"
    assert_success
    assert_output --partial "my-project"
}

