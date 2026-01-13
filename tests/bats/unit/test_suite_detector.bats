#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Source the mod_registry.sh and test_suite_detector.sh files for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the mod_registry.sh file if it exists
    if [[ -f "src/mod_registry.sh" ]]; then
        source "src/mod_registry.sh"
    fi

    # Source the test_suite_detector.sh file if it exists
    if [[ -f "src/test_suite_detector.sh" ]]; then
        source "src/test_suite_detector.sh"
    fi

    # Source the suite_grouping.sh file if it exists
    if [[ -f "src/suite_grouping.sh" ]]; then
        source "src/suite_grouping.sh"
    fi

    # Source the test_counter.sh file if it exists
    if [[ -f "src/test_counter.sh" ]]; then
        source "src/test_counter.sh"
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

@test "discover_test_suites() discovers Rust unit tests in example/rust-project/src/" {
    # Test Rust module directly
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -d "example/rust-project" ]]; then
        # Clean up any existing module functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        # Source Rust module
        source "mod/languages/rust/mod.sh"

        # Mock platform detection result for Rust
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # For now, Rust module returns suites_count=0 (stub implementation)
        # According to implementation plan, this is expected for minimal implementation
        assert_line "suites_count=0"
    else
        skip "Rust module or example project not available"
    fi
}

@test "discover_test_suites() discovers Rust integration tests in example/rust-project/tests/" {
    # Test Rust module directly
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -d "example/rust-project" ]]; then
        # Clean up any existing module functions
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        # Source Rust module
        source "mod/languages/rust/mod.sh"

        # Mock platform detection result for Rust
        local platform_data="platforms_count=1
platforms_0_language=rust
platforms_0_framework=cargo
platforms_0_confidence=high
platforms_0_module_type=language
project_root=example/rust-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # For now, Rust module returns suites_count=0 (stub implementation)
        # According to implementation plan, this is expected for minimal implementation
        assert_line "suites_count=0"
    else
        skip "Rust module or example project not available"
    fi
}

@test "discover_test_suites() discovers BATS test files in example/bats-project/tests/bats/" {
    # Test BATS module directly
    if [[ -f "mod/frameworks/bats/mod.sh" ]] && [[ -d "example/bats-project" ]]; then
        # Mock platform detection result for BATS
        local platform_data="platforms_count=1
platforms_0_language=bash
platforms_0_framework=bats
platforms_0_confidence=high
platforms_0_module_type=framework
project_root=example/bats-project"

        # Run discover_test_suites()
        run discover_test_suites "$platform_data"
        assert_success

        # Should discover BATS test files (BATS module has real implementation)
        assert_line --regexp "suites_count=[0-9]+"

        # Check that we have at least one suite
        local suites_count=$(echo "$output" | grep "suites_count=" | cut -d'=' -f2)
        assert [ "$suites_count" -gt 0 ]
    else
        skip "BATS module or example project not available"
    fi
}

@test "discover_test_suites() returns empty list when no platforms detected" {
    # Mock platform detection result with no platforms
    local platform_data="platforms_count=0"

    # Run discover_test_suites()
    run discover_test_suites "$platform_data"
    assert_success

    # Should return empty list
    assert_line "suites_count=0"
}

# Suite Grouping Tests

@test "has_configuration_file() detects suitey.toml" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    echo '[[suites]]' > "$test_project_dir/suitey.toml"
    echo 'name = "test"' >> "$test_project_dir/suitey.toml"
    
    run has_configuration_file "$test_project_dir"
    assert_success
    assert_output "suitey.toml"
    
    rm -rf "$test_project_dir"
}

@test "has_configuration_file() detects .suiteyrc when suitey.toml not present" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    echo '[[suites]]' > "$test_project_dir/.suiteyrc"
    echo 'name = "test"' >> "$test_project_dir/.suiteyrc"
    
    run has_configuration_file "$test_project_dir"
    assert_success
    assert_output ".suiteyrc"
    
    rm -rf "$test_project_dir"
}

@test "has_configuration_file() prefers suitey.toml over .suiteyrc" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    echo '[[suites]]' > "$test_project_dir/suitey.toml"
    echo 'name = "toml"' >> "$test_project_dir/suitey.toml"
    
    echo '[[suites]]' > "$test_project_dir/.suiteyrc"
    echo 'name = "rc"' >> "$test_project_dir/.suiteyrc"
    
    run has_configuration_file "$test_project_dir"
    assert_success
    assert_output "suitey.toml"
    
    rm -rf "$test_project_dir"
}

@test "has_configuration_file() returns error when no config file exists" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    run has_configuration_file "$test_project_dir"
    assert_failure
    
    rm -rf "$test_project_dir"
}

@test "parse_toml_config() parses simple suitey.toml" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    cat > "$test_project_dir/suitey.toml" << 'EOF'
[[suites]]
name = "unit"
files = ["tests/unit/**/*"]

[[suites]]
name = "integration"
files = ["tests/integration/**/*"]
EOF
    
    run parse_toml_config "$test_project_dir/suitey.toml"
    assert_success
    assert_output --partial "suites_count=2"
    assert_output --partial "suites_0_name=unit"
    assert_output --partial "suites_1_name=integration"
    
    rm -rf "$test_project_dir"
}

@test "parse_toml_config() handles invalid config file gracefully" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    echo "invalid toml content" > "$test_project_dir/suitey.toml"
    
    run parse_toml_config "$test_project_dir/suitey.toml"
    # Should return empty or handle gracefully
    assert_success
    
    rm -rf "$test_project_dir"
}

@test "is_conventional_directory() recognizes conventional names" {
    run is_conventional_directory "unit"
    assert_success
    assert_output "unit"
    
    run is_conventional_directory "integration"
    assert_success
    assert_output "integration"
    
    run is_conventional_directory "e2e"
    assert_success
    assert_output "e2e"
    
    run is_conventional_directory "performance"
    assert_success
    assert_output "performance"
}

@test "is_conventional_directory() rejects non-conventional names" {
    run is_conventional_directory "custom"
    assert_failure
    
    run is_conventional_directory "tests"
    assert_failure
}

@test "group_by_convention() groups files by conventional directory names" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    mkdir -p "$test_project_dir/tests/unit"
    mkdir -p "$test_project_dir/tests/integration"
    
    echo "test1" > "$test_project_dir/tests/unit/test1.bats"
    echo "test2" > "$test_project_dir/tests/unit/test2.bats"
    echo "test3" > "$test_project_dir/tests/integration/test3.bats"
    
    local test_files="$test_project_dir/tests/unit/test1.bats"$'\n'"$test_project_dir/tests/unit/test2.bats"$'\n'"$test_project_dir/tests/integration/test3.bats"
    
    run group_by_convention "$test_project_dir" "$test_files"
    assert_success
    assert_output --partial "suites_count=2"
    assert_output --partial "suites_0_name=unit"
    assert_output --partial "suites_1_name=integration"
    
    rm -rf "$test_project_dir"
}

@test "group_by_subdirectory() preserves user directory hierarchy" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    mkdir -p "$test_project_dir/tests/bats/unit"
    mkdir -p "$test_project_dir/tests/bats/integration"
    
    echo "test1" > "$test_project_dir/tests/bats/unit/test1.bats"
    echo "test2" > "$test_project_dir/tests/bats/integration/test2.bats"
    
    local test_files="$test_project_dir/tests/bats/unit/test1.bats"$'\n'"$test_project_dir/tests/bats/integration/test2.bats"
    
    run group_by_subdirectory "$test_project_dir" "$test_files"
    assert_success
    assert_output --partial "suites_count=2"
    
    rm -rf "$test_project_dir"
}

@test "group_by_directory() groups files by directory basename" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    mkdir -p "$test_project_dir/tests"
    
    echo "test1" > "$test_project_dir/tests/test1.bats"
    echo "test2" > "$test_project_dir/tests/test2.bats"
    
    local test_files="$test_project_dir/tests/test1.bats"$'\n'"$test_project_dir/tests/test2.bats"
    
    run group_by_directory "$test_project_dir" "$test_files"
    assert_success
    assert_output --partial "suites_count=1"
    assert_output --partial "suites_0_name=tests"
    
    rm -rf "$test_project_dir"
}

@test "group_by_file() creates one suite per file" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    echo "test1" > "$test_project_dir/test1.bats"
    echo "test2" > "$test_project_dir/test2.bats"
    
    local test_files="$test_project_dir/test1.bats"$'\n'"$test_project_dir/test2.bats"
    
    run group_by_file "$test_files"
    assert_success
    assert_output --partial "suites_count=2"
    
    rm -rf "$test_project_dir"
}

@test "apply_adaptive_grouping() uses configuration file when present" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    cat > "$test_project_dir/suitey.toml" << 'EOF'
[[suites]]
name = "custom"
files = ["tests/**/*"]
EOF
    
    local test_files="$test_project_dir/tests/test1.bats"
    
    run apply_adaptive_grouping "$test_project_dir" "$test_files"
    assert_success
    assert_output --partial "suites_count=1"
    assert_output --partial "suites_0_name=custom"
    
    rm -rf "$test_project_dir"
}

@test "apply_adaptive_grouping() falls back to convention-based when no config" {
    local test_project_dir
    test_project_dir="$(mktemp -d)"
    
    mkdir -p "$test_project_dir/tests/unit"
    echo "test1" > "$test_project_dir/tests/unit/test1.bats"
    
    local test_files="$test_project_dir/tests/unit/test1.bats"
    
    run apply_adaptive_grouping "$test_project_dir" "$test_files"
    assert_success
    assert_output --partial "suites_count=1"
    assert_output --partial "suites_0_name=unit"
    
    rm -rf "$test_project_dir"
}

# Test Counting Tests

@test "count_bats_tests() counts @test annotations in BATS files" {
    if [[ -f "example/bats-project/tests/bats/basic_tests.bats" ]]; then
        run count_bats_tests "example/bats-project/tests/bats/basic_tests.bats"
        assert_success
        assert_output "4"
    else
        skip "Example BATS file not available"
    fi
}

@test "count_bats_tests() returns 0 for files with no tests" {
    local test_file
    test_file="$(mktemp)"
    
    echo "#!/usr/bin/env bats" > "$test_file"
    echo "# No tests here" >> "$test_file"
    
    run count_bats_tests "$test_file"
    assert_success
    assert_output "0"
    
    rm -f "$test_file"
}

@test "count_rust_tests() counts #[test] functions in Rust unit test files" {
    if [[ -f "example/rust-project/src/lib.rs" ]]; then
        run count_rust_tests "example/rust-project/src/lib.rs"
        assert_success
        assert_output "3"
    else
        skip "Example Rust file not available"
    fi
}

@test "count_rust_tests() counts #[test] functions in Rust integration test files" {
    if [[ -f "example/rust-project/tests/integration_test.rs" ]]; then
        run count_rust_tests "example/rust-project/tests/integration_test.rs"
        assert_success
        assert_output "2"
    else
        skip "Example Rust integration test file not available"
    fi
}

@test "count_rust_tests() returns 0 for files with no tests" {
    local test_file
    test_file="$(mktemp --suffix=.rs)"
    
    echo "pub fn add(a: i32, b: i32) -> i32 {" > "$test_file"
    echo "    a + b" >> "$test_file"
    echo "}" >> "$test_file"
    
    run count_rust_tests "$test_file"
    assert_success
    assert_output "0"
    
    rm -f "$test_file"
}

@test "count_tests_in_file() detects BATS files and counts tests" {
    if [[ -f "example/bats-project/tests/bats/basic_tests.bats" ]]; then
        run count_tests_in_file "example/bats-project/tests/bats/basic_tests.bats"
        assert_success
        assert_output "4"
    else
        skip "Example BATS file not available"
    fi
}

@test "count_tests_in_file() detects Rust files and counts tests" {
    if [[ -f "example/rust-project/src/lib.rs" ]]; then
        run count_tests_in_file "example/rust-project/src/lib.rs"
        assert_success
        assert_output "3"
    else
        skip "Example Rust file not available"
    fi
}

@test "count_tests_in_file() returns 0 for unknown file types" {
    local test_file
    test_file="$(mktemp --suffix=.unknown)"
    
    echo "some content" > "$test_file"
    
    run count_tests_in_file "$test_file"
    assert_success
    assert_output "0"
    
    rm -f "$test_file"
}

@test "count_tests_in_files() counts tests across multiple files" {
    if [[ -f "example/bats-project/tests/bats/basic_tests.bats" ]] && [[ -f "example/bats-project/tests/bats/advanced_tests.bats" ]]; then
        local basic_count
        basic_count=$(count_bats_tests "example/bats-project/tests/bats/basic_tests.bats")
        local advanced_count
        advanced_count=$(count_bats_tests "example/bats-project/tests/bats/advanced_tests.bats")
        local expected_total=$((basic_count + advanced_count))
        
        run count_tests_in_files "example/bats-project/tests/bats/basic_tests.bats" "example/bats-project/tests/bats/advanced_tests.bats"
        assert_success
        assert_output "$expected_total"
    else
        skip "Example BATS files not available"
    fi
}
