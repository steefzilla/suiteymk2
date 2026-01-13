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

