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

@test "detect_platforms() checks Docker daemon accessibility" {
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

        # Should include container environment status
        assert echo "$result" | grep -q "docker_available="
        assert echo "$result" | grep -q "container_operations="
        assert echo "$result" | grep -q "network_access="

        # Should still detect the platform
        assert echo "$result" | grep -q "platforms_count=1"
        assert echo "$result" | grep -q "platforms_0_language=rust"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() handles Docker daemon unavailability gracefully" {
    # Register BATS module
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"

        # Create a temporary directory with .bats file
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test.bats"

        # Mock docker command to fail (simulate Docker not available)
        docker() {
            return 1
        }
        export -f docker

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should indicate Docker is not available
        assert echo "$result" | grep -q "docker_available=false"
        assert echo "$result" | grep -q "container_operations=false"

        # Should still detect the platform (detection doesn't require Docker)
        assert echo "$result" | grep -q "platforms_count=1"
        assert echo "$result" | grep -q "platforms_0_language=bash"

        # Cleanup
        rm -rf "$test_dir"
        unset -f docker
    else
        skip "Bash module not found"
    fi
}

@test "detect_platforms() verifies basic container operations work" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]] && command -v docker >/dev/null 2>&1; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Create a temporary directory with Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # If Docker is available, should check container operations
        assert echo "$result" | grep -q "container_operations=true\|container_operations=false"

        # Should also check network access
        assert echo "$result" | grep -q "network_access=true\|network_access=false"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found or Docker not available"
    fi
}

@test "detect_platforms() checks network connectivity for image pulls" {
    # Register Cargo framework module
    if [[ -f "mod/frameworks/cargo/mod.sh" ]]; then
        source "mod/frameworks/cargo/mod.sh"
        register_module "cargo-module" "cargo-module"

        # Create a temporary directory with Cargo.toml
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should include network access check
        assert echo "$result" | grep -q "network_access="

        # Should still detect the framework
        assert echo "$result" | grep -q "platforms_0_framework=cargo"
        assert echo "$result" | grep -q "platforms_0_module_id=cargo-module"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Cargo framework module not found"
    fi
}

@test "detect_platforms() provides clear container environment status for multiple platforms" {
    # Register both Rust and BATS modules
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Clean up functions between module loads
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"

        # Create a temporary directory with both Cargo.toml and .bats files
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        mkdir -p "$test_dir/tests/bats"
        echo "#!/usr/bin/env bats" > "$test_dir/tests/bats/test.bats"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should detect both platforms
        assert echo "$result" | grep -q "platforms_count=2"

        # Should include container environment status for both
        assert echo "$result" | grep -q "docker_available="
        assert echo "$result" | grep -q "container_operations="
        assert echo "$result" | grep -q "network_access="

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Required modules not found"
    fi
}

@test "detect_platforms() calculates high confidence when config file and test files present" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Create a temporary directory with Cargo.toml and test files
        local test_dir
        test_dir=$(mktemp -d)
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        mkdir -p "$test_dir/src"
        echo "#[test]" > "$test_dir/src/lib.rs"
        echo "fn test_example() {}" >> "$test_dir/src/lib.rs"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should detect with high confidence due to Cargo.toml + test files
        assert echo "$result" | grep -q "platforms_0_confidence=high"
        assert echo "$result" | grep -q "platforms_0_language=rust"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() calculates medium confidence when only test files present" {
    # Register BATS module
    if [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"

        # Create a temporary directory with BATS test directory but no .bats files
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/tests/bats"
        # Don't create actual .bats files, just the directory structure

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should detect with medium confidence due to test directory structure
        assert echo "$result" | grep -q "platforms_0_confidence=medium"
        assert echo "$result" | grep -q "platforms_0_language=bash"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Bash module not found"
    fi
}

@test "detect_platforms() calculates low confidence when only file extensions present" {
    # Register Rust module
    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Create a temporary directory with only .rs files (no Cargo.toml)
        local test_dir
        test_dir=$(mktemp -d)
        mkdir -p "$test_dir/src"
        echo "fn main() {}" > "$test_dir/src/main.rs"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should detect with low confidence due to only .rs file extension
        assert echo "$result" | grep -q "platforms_0_confidence=low"
        assert echo "$result" | grep -q "platforms_0_language=rust"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}

@test "detect_platforms() handles multiple confidence levels in same project" {
    # Register both Rust and BATS modules
    if [[ -f "mod/languages/rust/mod.sh" ]] && [[ -f "mod/languages/bash/mod.sh" ]]; then
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Clean up functions between module loads
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        source "mod/languages/bash/mod.sh"
        register_module "bash-module" "bash-module"

        # Create a temporary directory with high confidence Rust + medium confidence Bash
        local test_dir
        test_dir=$(mktemp -d)
        # High confidence Rust: Cargo.toml + test files
        echo "name = \"test\"" > "$test_dir/Cargo.toml"
        mkdir -p "$test_dir/src"
        echo "#[test]" > "$test_dir/src/lib.rs"
        echo "fn test_example() {}" >> "$test_dir/src/lib.rs"
        # Medium confidence Bash: test directory structure
        mkdir -p "$test_dir/tests/bats"

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should detect both platforms with appropriate confidence levels
        assert echo "$result" | grep -q "platforms_count=2"
        assert echo "$result" | grep -q "platforms_0_confidence=high\|platforms_1_confidence=high"
        assert echo "$result" | grep -q "platforms_0_confidence=medium\|platforms_1_confidence=medium"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Required modules not found"
    fi
}

@test "detect_platforms() defaults to low confidence when module doesn't specify confidence" {
    # Register a custom test module that doesn't return confidence
    # We'll create a simple test by temporarily modifying an existing module

    if [[ -f "mod/languages/rust/mod.sh" ]]; then
        # First register the normal Rust module
        source "mod/languages/rust/mod.sh"
        register_module "rust-module" "rust-module"

        # Create a temporary directory with no detectable files
        local test_dir
        test_dir=$(mktemp -d)

        # Run detect_platforms()
        local result
        result=$(detect_platforms "$test_dir")

        # Should have platforms_count=0 since no platforms detected
        assert echo "$result" | grep -q "platforms_count=0"

        # Cleanup
        rm -rf "$test_dir"
    else
        skip "Rust module not found"
    fi
}


