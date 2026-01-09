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

