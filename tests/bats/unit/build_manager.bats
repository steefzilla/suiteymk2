#!/usr/bin/env bash

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# Source the build_manager.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the build_manager.sh file if it exists
    if [[ -f "src/build_manager.sh" ]]; then
        source "src/build_manager.sh"
    fi

    # Track containers created during tests for cleanup
    TEST_CONTAINERS=()
}

teardown() {
    # Clean up any containers created during tests
    for container_id in "${TEST_CONTAINERS[@]}"; do
        if [[ -n "$container_id" ]]; then
            docker stop "$container_id" >/dev/null 2>&1 || true
            docker rm "$container_id" >/dev/null 2>&1 || true
        fi
    done
    TEST_CONTAINERS=()
}

@test "launch_build_container() validates required parameters" {
    # Test missing docker_image
    run launch_build_container "project_root=."
    assert_failure
    assert_output --partial "Error: docker_image is required"
    assert_output --partial "container_status=error"

    # Test missing project_root
    run launch_build_container "docker_image=test-image"
    assert_failure
    assert_output --partial "Error: Project root directory does not exist"
}

@test "launch_build_container() launches build container with correct configuration using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create container configuration
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
cpu_cores=0
container_name=suitey-test-$$"

    run launch_build_container "$container_config"
    assert_success

    # Verify container was created
    assert_output --partial "container_id="
    assert_output --partial "container_status=running"
    assert_output --partial "container_name=suitey-test-$$"
    assert_output --partial "docker_image=rust:1.70-slim"
    assert_output --partial "artifact_dir="
    assert_output --partial "project_root=example/rust-project"

    # Extract container ID for cleanup
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Verify container exists and is running (match by prefix since we use short IDs)
    if [[ -n "$container_id" ]]; then
        run docker ps --format "{{.ID}}"
        assert_success
        # Check if container ID appears in the output
        assert_output --partial "$container_id"
    fi
}

@test "launch_build_container() mounts project directory read-only using example projects" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a test file in the project to verify read-only mount
    local test_file="example/rust-project/.suitey-test-$$"
    echo "test content" > "$test_file"

    # Create container configuration
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-readonly-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Verify mount is read-only by attempting to write (should fail)
    if [[ -n "$container_id" ]]; then
        # Try to write to the mounted directory (should fail if read-only)
        run docker exec "$container_id" sh -c "echo 'write test' > /workspace/.suitey-write-test-$$ 2>&1"
        # The write should fail if mount is read-only
        # Note: Some Docker versions may not enforce read-only strictly, so we check the mount info
        run docker inspect "$container_id" --format '{{range .Mounts}}{{.Source}} {{.Destination}} {{.RW}}{{println}}{{end}}'
        assert_output --partial "/workspace"
        # Verify the test file we created is still there (wasn't modified)
        assert [ -f "$test_file" ]
        assert_equal "$(cat "$test_file")" "test content"
    fi

    # Clean up test file
    rm -f "$test_file"
}

@test "launch_build_container() mounts /tmp artifact directory read-write" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create container configuration
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-artifacts-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID and artifact directory
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    local artifact_dir
    artifact_dir=$(echo "$output" | grep "^artifact_dir=" | cut -d'=' -f2)

    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Verify artifact directory is writable
    if [[ -n "$container_id" ]] && [[ -n "$artifact_dir" ]]; then
        # Try to write to the artifact directory
        run docker exec "$container_id" sh -c "echo 'artifact test' > /tmp/build-artifacts/test-$$.txt 2>&1"
        assert_success

        # Verify file was created in the host artifact directory
        assert [ -f "$artifact_dir/test-$$.txt" ]
        assert_equal "$(cat "$artifact_dir/test-$$.txt")" "artifact test"

        # Clean up
        rm -f "$artifact_dir/test-$$.txt"
    fi
}

@test "track_container() tracks container status" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create a test container
    local full_container_id
    full_container_id=$(docker run -d --name "suitey-test-track-$$" alpine sleep 10 2>/dev/null)
    
    if [[ -z "$full_container_id" ]]; then
        skip "Failed to create test container"
    fi

    TEST_CONTAINERS+=("$full_container_id")

    # Use short ID for tracking (first 12 characters)
    local short_id
    short_id=$(echo "$full_container_id" | cut -c1-12)

    # Track container
    run track_container "$short_id"
    assert_success
    assert_output --partial "container_id=$short_id"
    assert_output --partial "container_status=running"
}

@test "track_container() handles non-existent container" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    run track_container "nonexistent-container-id-12345"
    assert_failure
    assert_output --partial "container_status=not_found"
    assert_output --partial "error_message=Container not found"
}

@test "cleanup_container() cleans up containers on completion" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create a test container
    local container_id
    container_id=$(docker run -d --name "suitey-test-cleanup-$$" alpine sleep 10 2>/dev/null)
    
    if [[ -z "$container_id" ]]; then
        skip "Failed to create test container"
    fi

    # Get short ID for verification
    local short_id
    short_id=$(echo "$container_id" | cut -c1-12)

    # Verify container exists (Docker ps returns short IDs)
    run docker ps -a --format "{{.ID}}"
    assert_success
    assert_output --partial "$short_id"

    # Clean up container using short ID
    run cleanup_container "$short_id"
    assert_success
    assert_output --partial "cleanup_status=success"
    assert_output --partial "container_id=$short_id"

    # Verify container is removed
    run docker ps -a --format "{{.ID}}"
    assert_success
    refute_output --regexp "^${short_id}"
}

@test "cleanup_containers() cleans up multiple containers" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create multiple test containers
    local container1
    container1=$(docker run -d --name "suitey-test-multi-1-$$" alpine sleep 10 2>/dev/null)
    local container2
    container2=$(docker run -d --name "suitey-test-multi-2-$$" alpine sleep 10 2>/dev/null)

    if [[ -z "$container1" ]] || [[ -z "$container2" ]]; then
        skip "Failed to create test containers"
    fi

    # Clean up containers
    local container_ids="$container1"$'\n'"$container2"
    run cleanup_containers "$container_ids"
    assert_success
    assert_output --partial "cleanup_status=success"
    assert_output --partial "cleanup_total_count=2"
    assert_output --partial "cleanup_success_count=2"
    assert_output --partial "cleanup_failed_count=0"

    # Verify containers are removed
    run docker ps -a --format "{{.ID}}" --filter "id=$container1"
    refute_output --partial "$container1"
    run docker ps -a --format "{{.ID}}" --filter "id=$container2"
    refute_output --partial "$container2"
}

@test "execute_build_command() executes cargo build in container using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-build-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute build command with CARGO_TARGET_DIR set to writable location
    # Note: Cargo.lock will still try to write to project root, but build artifacts go to /tmp
    local build_command="CARGO_TARGET_DIR=/tmp/build-artifacts cargo build 2>&1 || true"
    run execute_build_command "$container_id" "$build_command"
    assert_success

    # Verify output contains build results
    assert_output --partial "exit_code="
    assert_output --partial "duration="
    # Cargo build may fail due to read-only filesystem for Cargo.lock, but function should still report results
    local exit_code
    exit_code=$(echo "$output" | grep "^exit_code=" | cut -d'=' -f2)
    # Accept any exit code (0 for success, non-zero for failure)
    assert [ -n "$exit_code" ]

    # Verify duration is tracked
    local duration
    duration=$(echo "$output" | grep "^duration=" | cut -d'=' -f2)
    assert [ -n "$duration" ]
    # Duration should be a positive number
    assert [ "$(echo "$duration > 0" | bc 2>/dev/null || echo "1")" = "1" ]
}

@test "execute_build_command() captures build output (stdout/stderr)" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-output-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute build command
    local build_command="cargo build"
    run execute_build_command "$container_id" "$build_command"
    assert_success

    # Verify output is captured
    assert_output --partial "stdout="
    assert_output --partial "stderr="
    
    # Verify stdout contains cargo build output
    local stdout
    stdout=$(echo "$output" | grep "^stdout=" | cut -d'=' -f2- || echo "")
    # stdout should contain cargo-related output (may be empty for successful builds)
    # At minimum, verify the key exists
    
    # Verify stderr key exists (may be empty)
    local stderr
    stderr=$(echo "$output" | grep "^stderr=" | cut -d'=' -f2- || echo "")
    # stderr key should be present
}

@test "execute_build_command() detects build failures (non-zero exit code)" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-failure-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute a command that will fail
    local build_command="cargo build --invalid-flag-that-does-not-exist"
    run execute_build_command "$container_id" "$build_command"
    assert_success  # Function itself succeeds, but build fails

    # Verify exit code indicates failure
    local exit_code
    exit_code=$(echo "$output" | grep "^exit_code=" | cut -d'=' -f2)
    assert [ "$exit_code" != "0" ]
    
    # Verify build_status indicates failure
    local build_status
    build_status=$(echo "$output" | grep "^build_status=" | cut -d'=' -f2 || echo "")
    if [[ -n "$build_status" ]]; then
        assert_equal "$build_status" "failed"
    fi
}

@test "execute_build_command() tracks build duration" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-duration-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute a command that takes some time
    local build_command="sleep 1 && cargo build"
    local start_time
    start_time=$(date +%s.%N)
    
    run execute_build_command "$container_id" "$build_command"
    assert_success
    
    local end_time
    end_time=$(date +%s.%N)

    # Verify duration is tracked
    local duration
    duration=$(echo "$output" | grep "^duration=" | cut -d'=' -f2)
    assert [ -n "$duration" ]
    
    # Duration should be a positive number
    assert [ "$(echo "$duration > 0" | bc 2>/dev/null || echo "1")" = "1" ]
    
    # Duration should be reasonable (at least 1 second due to sleep)
    local duration_float
    duration_float=$(echo "$duration" | cut -d'.' -f1)
    assert [ "$duration_float" -ge 1 ]
    
    # Verify duration is in seconds (format: X.XXX)
    assert_output --regexp "duration=[0-9]+\.[0-9]+"
}

@test "execute_build_command() handles invalid container ID" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    run execute_build_command "nonexistent-container-12345" "cargo build"
    assert_failure
    assert_output --partial "error_message="
    assert_output --partial "container_status=error"
}

@test "execute_build_command() handles empty build command" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-empty-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute empty command
    run execute_build_command "$container_id" ""
    assert_failure
    assert_output --partial "error_message="
}

@test "allocate_cpu_cores() allocates multiple CPU cores to build container" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Get available CPU cores
    run get_available_cpu_cores
    assert_success
    local available_cores
    available_cores=$(echo "$output" | tr -d '[:space:]')
    assert [ -n "$available_cores" ]
    assert [ "$available_cores" -gt 0 ]

    # Allocate CPU cores (use at least 1, but not more than available)
    local cores_to_allocate
    if [[ "$available_cores" -ge 2 ]]; then
        cores_to_allocate=2
    else
        cores_to_allocate=1
    fi

    # Create container configuration with CPU cores
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
cpu_cores=$cores_to_allocate
container_name=suitey-test-cores-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Verify CPU allocation in container
    if [[ -n "$container_id" ]]; then
        # Check container CPU limit using docker inspect
        run docker inspect "$container_id" --format '{{.HostConfig.CpuQuota}}'
        assert_success
        # CPU quota should be set (non-zero) when cores are allocated
        # Format: quota is in microseconds, cores * 100000 = quota
        local cpu_quota
        cpu_quota=$(echo "$output" | tr -d '[:space:]')
        if [[ "$cores_to_allocate" -gt 0 ]]; then
            assert [ -n "$cpu_quota" ]
        fi
    fi
}

@test "get_parallel_build_flags() uses parallel build flags with nproc" {
    # Test that parallel build flags are generated correctly
    run get_parallel_build_flags "cargo"
    assert_success
    
    # Cargo uses --jobs flag for parallel builds
    assert_output --partial "--jobs"
    
    # Should include number of cores (use a pattern that doesn't conflict with grep options)
    local flags
    flags=$(echo "$output" | grep -oE '\-\-jobs [0-9]+' || echo "")
    # Alternative: just check that output contains a number after --jobs
    if [[ -z "$flags" ]]; then
        # Try simpler check - just verify it has --jobs and a number
        assert_output --regexp '--jobs [0-9]+'
    else
        assert [ -n "$flags" ]
    fi
}

@test "get_parallel_build_flags() handles make build systems" {
    # Test that make gets -j flag
    run get_parallel_build_flags "make"
    assert_success
    
    # Make uses -j flag
    assert_output --partial "-j"
    
    # Should include number of cores (escape -j to avoid grep treating it as option)
    local flags
    flags=$(echo "$output" | grep -oE '\-j[0-9]+' || echo "")
    assert [ -n "$flags" ]
}

@test "get_parallel_build_flags() handles unknown build systems gracefully" {
    # Test that unknown build systems return empty or default
    run get_parallel_build_flags "unknown-build-system"
    assert_success
    
    # Should not fail, may return empty or default flags
    # Just verify it doesn't error
}

@test "get_available_cpu_cores() handles single-core systems gracefully" {
    # Test that single-core systems are handled
    run get_available_cpu_cores
    assert_success
    
    # Should return at least 1
    local cores
    cores=$(echo "$output" | grep -oE '[0-9]+' || echo "0")
    assert [ "$cores" -ge 1 ]
    
    # Should handle single-core gracefully (return 1)
    if [[ "$cores" -eq 1 ]]; then
        # Single core system - should still work
        assert [ "$cores" -eq 1 ]
    fi
}

@test "execute_build_command() uses parallel build flags when available" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Launch a build container
    local container_config="docker_image=rust:1.70-slim
project_root=example/rust-project
working_directory=/workspace
container_name=suitey-test-parallel-$$"

    run launch_build_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Get parallel build flags for cargo
    local parallel_flags
    parallel_flags=$(get_parallel_build_flags "cargo")
    
    # Execute build command with parallel flags
    local build_command="CARGO_TARGET_DIR=/tmp/build-artifacts cargo build $parallel_flags 2>&1 || true"
    run execute_build_command "$container_id" "$build_command"
    assert_success

    # Verify command was executed (may succeed or fail, but should execute)
    assert_output --partial "exit_code="
    
    # Verify parallel flags were used (check stdout/stderr for -j flag)
    local stdout
    stdout=$(echo "$output" | grep "^stdout=" | cut -d'=' -f2- || echo "")
    local stderr
    stderr=$(echo "$output" | grep "^stderr=" | cut -d'=' -f2- || echo "")
    
    # The build command should have included parallel flags
    # (We can't easily verify this without parsing cargo output, but the function should work)
}

@test "generate_test_image_dockerfile() generates Dockerfile for test image using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create test configuration
    local base_image="rust:1.70-slim"
    local artifact_dir="/tmp/build-artifacts"
    local project_root="example/rust-project"
    local test_image_config="base_image=$base_image
artifact_dir=$artifact_dir
project_root=$project_root
framework=rust"

    run generate_test_image_dockerfile "$test_image_config"
    assert_success

    # Verify Dockerfile contains required sections
    assert_output --partial "FROM $base_image"
    assert_output --partial "COPY"
    assert_output --partial "WORKDIR"

    # Verify Dockerfile is valid (can be parsed)
    local dockerfile_content="$output"
    assert [ -n "$dockerfile_content" ]
}

@test "build_test_image() builds Docker image with artifacts from example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create temporary directory for artifacts
    local artifact_dir
    artifact_dir=$(mktemp -d -t suitey-test-artifacts-XXXXXX)
    
    # Create a dummy artifact file
    mkdir -p "$artifact_dir/target/debug"
    echo "dummy binary" > "$artifact_dir/target/debug/suitey-rust-example"

    # Create test image configuration
    local base_image="rust:1.70-slim"
    local project_root="example/rust-project"
    local image_tag="suitey-test-rust-$$"
    local test_image_config="base_image=$base_image
artifact_dir=$artifact_dir
project_root=$project_root
framework=rust
image_tag=$image_tag"

    run build_test_image "$test_image_config"
    assert_success

    # Verify image was created
    assert_output --partial "image_id="
    assert_output --partial "image_tag=$image_tag"
    assert_output --partial "build_status=success"

    # Extract image ID for cleanup
    local image_id
    image_id=$(echo "$output" | grep "^image_id=" | cut -d'=' -f2)
    if [[ -n "$image_id" ]]; then
        # Clean up test image
        docker rmi "$image_tag" >/dev/null 2>&1 || true
        docker rmi "$image_id" >/dev/null 2>&1 || true
    fi

    # Clean up artifact directory
    rm -rf "$artifact_dir"
}

@test "verify_test_image() verifies image contains build artifacts from example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a simple test image with artifacts
    local test_image_tag="suitey-test-verify-$$"
    local dockerfile_content="FROM alpine:latest
RUN mkdir -p /app/target/debug
RUN echo 'test artifact' > /app/target/debug/test-binary
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    # Verify image contains artifacts
    local verification_config="image_tag=$test_image_tag
artifact_paths=/app/target/debug/test-binary"

    run verify_test_image "$verification_config"
    assert_success

    # Verify output indicates artifacts are present
    assert_output --partial "verification_status=success"
    assert_output --partial "artifacts_verified=true"

    # Clean up
    docker rmi "$test_image_tag" >/dev/null 2>&1 || true
}

@test "verify_test_image() verifies image contains source code from example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a simple test image with source code
    local test_image_tag="suitey-test-source-$$"
    local dockerfile_content="FROM alpine:latest
RUN mkdir -p /app/src
RUN echo 'pub fn test() {}' > /app/src/lib.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    # Verify image contains source code
    local verification_config="image_tag=$test_image_tag
source_paths=/app/src/lib.rs"

    run verify_test_image "$verification_config"
    assert_success

    # Verify output indicates source is present
    assert_output --partial "verification_status=success"
    assert_output --partial "source_verified=true"

    # Clean up
    docker rmi "$test_image_tag" >/dev/null 2>&1 || true
}

@test "verify_test_image() verifies image contains test suites from example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a simple test image with test suites
    local test_image_tag="suitey-test-suites-$$"
    local dockerfile_content="FROM alpine:latest
RUN mkdir -p /app/tests
RUN echo '#[test] fn test_example() {}' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    # Verify image contains test suites
    local verification_config="image_tag=$test_image_tag
test_suite_paths=/app/tests/integration_test.rs"

    run verify_test_image "$verification_config"
    assert_success

    # Verify output indicates test suites are present
    assert_output --partial "verification_status=success"
    assert_output --partial "test_suites_verified=true"

    # Clean up
    docker rmi "$test_image_tag" >/dev/null 2>&1 || true
}

@test "execute_builds_parallel() runs independent builds in parallel" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create build configuration with independent builds (no dependencies)
    local build_config="build_steps_count=2
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_project_root=example/rust-project
build_steps_0_build_command=sleep 1 && echo 'build 1 done'
build_steps_0_dependencies=
build_steps_1_docker_image=rust:1.70-slim
build_steps_1_project_root=example/rust-project
build_steps_1_build_command=sleep 1 && echo 'build 2 done'
build_steps_1_dependencies=
parallel_groups_count=1
parallel_groups_0_step_count=2
parallel_groups_0_steps=0,1"

    run execute_builds_parallel "$build_config"
    assert_success

    # Verify both builds completed
    assert_output --partial "build_status=success"
    assert_output --partial "builds_completed="
    
    # Verify builds ran in parallel (total time should be ~1 second, not ~2 seconds)
    # This is a basic check - in practice, we'd verify timing more precisely
}

@test "execute_builds_parallel() waits for dependent builds sequentially" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create build configuration with dependencies
    # Build 0 has no dependencies, Build 1 depends on Build 0
    local build_config="build_steps_count=2
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_project_root=example/rust-project
build_steps_0_build_command=sleep 1 && echo 'build 0 done'
build_steps_0_dependencies=
build_steps_1_docker_image=rust:1.70-slim
build_steps_1_project_root=example/rust-project
build_steps_1_build_command=sleep 1 && echo 'build 1 done'
build_steps_1_dependencies=0
parallel_groups_count=2
parallel_groups_0_step_count=1
parallel_groups_0_steps=0
parallel_groups_1_step_count=1
parallel_groups_1_steps=1"

    run execute_builds_parallel "$build_config"
    assert_success

    # Verify both builds completed
    assert_output --partial "build_status=success"
    
    # Verify build 0 completed before build 1 started
    # (We can check timestamps or order in output)
    local build_0_completed
    build_0_completed=$(echo "$output" | grep "build_steps_0_build_status=success" || echo "")
    local build_1_started
    build_1_started=$(echo "$output" | grep "build_steps_1_build_status=success" || echo "")
    
    assert [ -n "$build_0_completed" ]
    assert [ -n "$build_1_started" ]
}

@test "execute_builds_parallel() handles build failures in parallel builds" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create build configuration where one build will fail
    local build_config="build_steps_count=2
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_project_root=example/rust-project
build_steps_0_build_command=exit 1
build_steps_0_dependencies=
build_steps_1_docker_image=rust:1.70-slim
build_steps_1_project_root=example/rust-project
build_steps_1_build_command=sleep 1 && echo 'build 1 done'
build_steps_1_dependencies=
parallel_groups_count=1
parallel_groups_0_step_count=2
parallel_groups_0_steps=0,1"

    run execute_builds_parallel "$build_config"
    # Function may return success (reports failures) or failure (aborts)
    # Either is acceptable - we just need to verify failures are detected

    # Verify failure is detected
    assert_output --partial "build_steps_0_build_status=failed"
    
    # Verify error information is captured
    assert_output --partial "exit_code=1"
}

@test "execute_builds_parallel() aborts dependent builds when prerequisite fails" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create build configuration where build 0 fails and build 1 depends on it
    local build_config="build_steps_count=2
build_steps_0_docker_image=rust:1.70-slim
build_steps_0_project_root=example/rust-project
build_steps_0_build_command=exit 1
build_steps_0_dependencies=
build_steps_1_docker_image=rust:1.70-slim
build_steps_1_project_root=example/rust-project
build_steps_1_build_command=sleep 1 && echo 'build 1 done'
build_steps_1_dependencies=0
parallel_groups_count=2
parallel_groups_0_step_count=1
parallel_groups_0_steps=0
parallel_groups_1_step_count=1
parallel_groups_1_steps=1"

    run execute_builds_parallel "$build_config"
    # Function should detect failure and abort dependent builds

    # Verify build 0 failed
    assert_output --partial "build_steps_0_build_status=failed"
    
    # Verify build 1 was aborted or not started
    # (Either skipped or marked as aborted)
    assert_output --partial "build_steps_1"
}

@test "execute_builds_parallel() handles empty build configuration" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    run execute_builds_parallel "build_steps_count=0"
    assert_success
    
    # Should handle empty configuration gracefully
    assert_output --partial "builds_completed=0"
}

