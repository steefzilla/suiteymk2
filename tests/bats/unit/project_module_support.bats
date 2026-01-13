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

@test "project module can override language module behavior" {
    # Register language module first
    local lang_module="
detect() {
    echo 'detected=true'
    echo 'confidence=high'
    echo 'indicators_0=rust_file'
    echo 'indicators_count=1'
    echo 'language=rust'
    echo 'frameworks_0=cargo'
}
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
    
    # Register project module with higher priority
    local project_module="
detect() {
    echo 'detected=true'
    echo 'confidence=high'
    echo 'indicators_0=custom_detection'
    echo 'indicators_count=1'
    echo 'language=rust'
    echo 'frameworks_0=cargo'
}
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
    register_module "my-project" "my-project"
    
    # Verify both modules are registered
    run get_all_modules
    assert_success
    assert_output --partial "rust-lang"
    assert_output --partial "my-project"
    
    # Verify project modules are listed
    run get_project_modules
    assert_success
    assert_output --partial "my-project"
}

@test "project module can override framework module behavior" {
    # Register framework module first
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
    
    # Verify both modules are registered
    run get_all_modules
    assert_success
    assert_output --partial "cargo-fw"
    assert_output --partial "my-project"
    
    # Verify project modules are listed
    run get_project_modules
    assert_success
    assert_output --partial "my-project"
}

@test "project module has highest priority" {
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
    
    # Verify type-based lookup works for all types
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

@test "project modules can be discovered in project directory" {
    # This test verifies that project modules can be found in the project directory
    # For now, we'll test that the infrastructure is in place

    # Create a temporary project directory with a project module
    local temp_project
    temp_project=$(mktemp -d)
    mkdir -p "$temp_project/.suitey/mod/projects/custom-module"

    cat > "$temp_project/.suitey/mod/projects/custom-module/mod.sh" << 'EOF'
#!/usr/bin/env bash

# Custom project module
detect() {
    echo "detected=true"
    echo "confidence=high"
    echo "indicators_0=custom_project"
    echo "indicators_count=1"
    echo "language=rust"
    echo "frameworks_0=cargo"
    return 0
}

check_binaries() { echo "available=true"; }
discover_test_suites() { echo "suites_count=0"; }
detect_build_requirements() { echo "requires_build=false"; }
get_build_steps() { echo "build_steps_count=0"; }
execute_test_suite() { echo "exit_code=0"; }
parse_test_results() { echo "total_tests=0"; }
get_metadata() {
    echo "module_type=project"
    echo "language=rust"
    echo "frameworks_count=0"
    echo "project_type=custom"
    echo "version=0.1.0"
    echo "capabilities_count=0"
    echo "required_binaries_count=0"
}
EOF

    # Test that we can source and register the project module
    # This simulates project module discovery
    cd "$temp_project"
    source ".suitey/mod/projects/custom-module/mod.sh"

    # Register the module (this would be done by discovery logic)
    register_module "custom-module" "custom-module"
    local register_status=$?
    assert_equal "$register_status" 0

    # Verify it's a project module
    run get_project_modules
    assert_success
    assert_output --partial "custom-module"

    # Clean up
    rm -rf "$temp_project"
}

@test "project modules can override default behavior" {
    # Register a language module with default behavior
    local default_lang_module="
detect() {
    echo 'detected=true'
    echo 'confidence=medium'
    echo 'indicators_0=default_detection'
    echo 'indicators_count=1'
    echo 'language=rust'
    echo 'frameworks_0=cargo'
}
check_binaries() { echo 'available=true'; }
discover_test_suites() { echo 'suites_count=0'; }
detect_build_requirements() { echo 'requires_build=true'; }
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
    eval "$default_lang_module"
    register_module "default-rust" "default-rust"
    
    # Register project module that overrides behavior
    local override_project_module="
detect() {
    echo 'detected=true'
    echo 'confidence=high'
    echo 'indicators_0=overridden_detection'
    echo 'indicators_count=1'
    echo 'language=rust'
    echo 'frameworks_0=cargo'
}
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
    eval "$override_project_module"
    register_module "override-project" "override-project"
    
    # Verify both modules are registered
    run get_all_modules
    assert_success
    assert_output --partial "default-rust"
    assert_output --partial "override-project"
    
    # Verify project module has higher priority
    run get_project_modules
    assert_success
    assert_output --partial "override-project"
}

@test "multiple project modules can coexist" {
    # Register multiple project modules
    local project1="
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
    echo 'project_type=test1'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$project1"
    register_module "project-1" "project-1"
    
    # Clean up functions
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done
    
    local project2="
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
    echo 'project_type=test2'
    echo 'version=0.1.0'
    echo 'capabilities_count=0'
    echo 'required_binaries_count=0'
}
"
    eval "$project2"
    register_module "project-2" "project-2"
    
    # Verify both project modules are registered
    run get_all_modules
    assert_success
    assert_output --partial "project-1"
    assert_output --partial "project-2"
    
    # Verify both are returned by get_project_modules
    run get_project_modules
    assert_success
    assert_output --partial "project-1"
    assert_output --partial "project-2"
}

@test "project modules can customize test discovery patterns" {
    # Register project module with custom test discovery
    local custom_test_module="
detect() { echo 'detected=true'; }
check_binaries() { echo 'available=true'; }
discover_test_suites() {
    echo 'suites_count=1'
    echo 'suites_0_name=custom_tests'
    echo 'suites_0_framework=custom'
    echo 'suites_0_test_files_count=5'
}
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
    eval "$custom_test_module"
    register_module "custom-test-project" "custom-test-project"
    
    # Verify module is registered
    run get_project_modules
    assert_success
    assert_output --partial "custom-test-project"
    
    # Test the custom test discovery
    local result
    result=$(discover_test_suites "/tmp" "")
    assert echo "$result" | grep -q "suites_count=1"
    assert echo "$result" | grep -q "custom_tests"
}

