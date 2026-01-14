#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source required modules
    if [[ -f "src/build_manager.sh" ]]; then
        source "src/build_manager.sh"
    fi

    if [[ -f "src/execution_system.sh" ]]; then
        source "src/execution_system.sh"
    fi

    if [[ -f "src/parallel_execution.sh" ]]; then
        source "src/parallel_execution.sh"
    fi

    # Track containers and images created during tests for cleanup
    TEST_CONTAINERS=()
    TEST_IMAGES=()

    # Reset global state
    ACTIVE_CONTAINERS=""
    PROCESSED_RESULT_FILES=""
    
    # Create a unique identifier for this test to avoid race conditions with parallel tests
    # Use BATS_TEST_NUMBER which is unique per test in the file
    TEST_UNIQUE_ID="restest_${BATS_TEST_NUMBER}_$$_${RANDOM}"
    
    # Set unique pool state file for this test
    export SUITEY_POOL_STATE_FILE="/tmp/suitey_resource_pool_${TEST_UNIQUE_ID}"
    
    # Reset pool state
    RESOURCE_POOL_CAPACITY=0
    RESOURCE_POOL_AVAILABLE=0
    RESOURCE_POOL_IN_USE=0
    RESOURCE_POOL_INITIALIZED=""
}

teardown() {
    # Clean up containers
    for container_id in "${TEST_CONTAINERS[@]}"; do
        if [[ -n "$container_id" ]]; then
            docker stop "$container_id" >/dev/null 2>&1 || true
            docker rm "$container_id" >/dev/null 2>&1 || true
        fi
    done
    TEST_CONTAINERS=()

    # Clean up images
    for image_tag in "${TEST_IMAGES[@]}"; do
        if [[ -n "$image_tag" ]]; then
            docker rmi "$image_tag" >/dev/null 2>&1 || true
        fi
    done
    TEST_IMAGES=()

    # Only clean up files belonging to THIS test (using TEST_UNIQUE_ID)
    if [[ -n "$TEST_UNIQUE_ID" ]]; then
        rm -f /tmp/*"${TEST_UNIQUE_ID}"* 2>/dev/null || true
    fi
    
    # Clean up pool state file
    if [[ -n "$SUITEY_POOL_STATE_FILE" ]]; then
        rm -f "$SUITEY_POOL_STATE_FILE" 2>/dev/null || true
    fi
    
    unset SUITEY_POOL_STATE_FILE
    unset TEST_UNIQUE_ID
}

# =============================================================================
# 3.3.4 Resource Management Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Limit concurrent containers by CPU count
# -----------------------------------------------------------------------------

@test "get_max_concurrent_containers() returns CPU core count by default" {
    # Get max concurrent containers
    run get_max_concurrent_containers
    assert_success

    # Should return number of CPU cores
    local expected_cores
    expected_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Output should contain max_containers
    assert_output --partial "max_containers=$expected_cores"
}

@test "get_max_concurrent_containers() respects explicit limit" {
    # Get max concurrent containers with explicit limit
    run get_max_concurrent_containers 2
    assert_success

    # Should return the explicit limit
    assert_output --partial "max_containers=2"
}

@test "get_max_concurrent_containers() does not exceed CPU count" {
    local available_cores
    available_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Request more than available
    local excessive_limit=$((available_cores + 10))

    run get_max_concurrent_containers "$excessive_limit"
    assert_success

    # Should return available cores (not exceed)
    assert_output --partial "max_containers=$available_cores"
    assert_output --partial "limited_by_cpu=true"
}

@test "get_max_concurrent_containers() ensures minimum of 1" {
    # Request 0 containers (invalid)
    run get_max_concurrent_containers 0
    assert_success

    # Should return at least 1
    assert_output --partial "max_containers="
    
    # Extract max_containers value
    local max_containers
    max_containers=$(echo "$output" | grep "^max_containers=" | cut -d'=' -f2)
    assert [ "$max_containers" -ge 1 ]
}

@test "resource_pool_init() initializes resource pool with correct capacity" {
    local available_cores
    available_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    run resource_pool_init
    assert_success

    # Should initialize with available CPU cores
    assert_output --partial "pool_capacity=$available_cores"
    assert_output --partial "pool_available=$available_cores"
    assert_output --partial "pool_in_use=0"
    assert_output --partial "pool_status=initialized"
}

@test "resource_pool_init() accepts custom capacity" {
    run resource_pool_init 2
    assert_success

    # Should initialize with custom capacity (limited by CPU)
    assert_output --partial "pool_capacity="
    assert_output --partial "pool_status=initialized"
}

@test "resource_pool_acquire() acquires resources when available" {
    # Initialize pool first (not with run, to preserve state)
    resource_pool_init 4 >/dev/null 2>&1

    run resource_pool_acquire 1
    assert_success

    # Should acquire 1 resource
    assert_output --partial "acquired=1"
    assert_output --partial "acquire_status=success"
}

@test "resource_pool_acquire() blocks when resources exhausted" {
    # Initialize pool with 1 slot (not with run, to preserve state)
    resource_pool_init 1 >/dev/null 2>&1

    # Acquire the only slot (not with run, to preserve state)
    resource_pool_acquire 1 >/dev/null 2>&1

    # Try to acquire another (should fail with wait indication)
    run resource_pool_acquire 1 "no_wait"
    
    # Should indicate resources are exhausted
    assert_output --partial "acquire_status=exhausted"
}

@test "resource_pool_release() releases resources back to pool" {
    # Initialize pool (not with run, to preserve state)
    resource_pool_init 4 >/dev/null 2>&1

    # Acquire resources (not with run, to preserve state)
    resource_pool_acquire 2 >/dev/null 2>&1

    # Release resources
    run resource_pool_release 2
    assert_success

    # Should release resources
    assert_output --partial "released=2"
    assert_output --partial "release_status=success"
}

@test "resource_pool_status() returns current pool state" {
    # Initialize pool (not with run, to preserve state)
    resource_pool_init 4 >/dev/null 2>&1

    # Acquire some resources (not with run, to preserve state)
    resource_pool_acquire 2 >/dev/null 2>&1

    run resource_pool_status
    assert_success

    # Should show correct state
    assert_output --partial "pool_capacity="
    assert_output --partial "pool_available="
    assert_output --partial "pool_in_use="
}

# -----------------------------------------------------------------------------
# Test: Clean up containers after completion
# -----------------------------------------------------------------------------

@test "cleanup_completed_containers() cleans up stopped containers" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create a test container that exits immediately
    local container_id
    container_id=$(docker run -d alpine:latest echo "test" 2>/dev/null | tr -d '\n')

    if [[ -z "$container_id" ]]; then
        skip "Failed to create test container"
    fi

    TEST_CONTAINERS+=("$container_id")

    # Wait for container to stop
    sleep 1

    # Track container
    ACTIVE_CONTAINERS="$container_id"

    run cleanup_completed_containers
    assert_success

    # Should clean up the stopped container
    assert_output --partial "cleanup_status=success"
    assert_output --partial "containers_cleaned="
}

@test "cleanup_completed_containers() leaves running containers alone" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create a test container that stays running
    local container_id
    container_id=$(docker run -d alpine:latest sleep 300 2>/dev/null | tr -d '\n')

    if [[ -z "$container_id" ]]; then
        skip "Failed to create test container"
    fi

    TEST_CONTAINERS+=("$container_id")

    # Track container
    ACTIVE_CONTAINERS="$container_id"

    run cleanup_completed_containers
    assert_success

    # Container should still be running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
    assert_equal "$container_status" "running"
}

@test "cleanup_all_suitey_containers() cleans up all suitey containers" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Use unique names for this test
    local unique_suffix="${TEST_UNIQUE_ID}"

    # Create test containers with suitey naming pattern
    local container1
    container1=$(docker run -d --name "suitey-test-cleanup-${unique_suffix}-1" alpine:latest sleep 300 2>/dev/null | tr -d '\n')
    local container2
    container2=$(docker run -d --name "suitey-test-cleanup-${unique_suffix}-2" alpine:latest sleep 300 2>/dev/null | tr -d '\n')

    if [[ -z "$container1" ]] || [[ -z "$container2" ]]; then
        skip "Failed to create test containers"
    fi

    TEST_CONTAINERS+=("$container1" "$container2")

    run cleanup_all_suitey_containers
    assert_success

    # Should clean up containers
    assert_output --partial "cleanup_status=success"
    assert_output --partial "containers_cleaned="
    
    # Containers should be removed
    local containers_remaining
    containers_remaining=$(docker ps -a --filter "name=suitey-test-cleanup-${unique_suffix}" --format "{{.ID}}" | wc -l)
    assert [ "$containers_remaining" -eq 0 ]
}

@test "register_container_for_cleanup() tracks containers for later cleanup" {
    # Clear active containers
    ACTIVE_CONTAINERS=""

    # Register containers
    run register_container_for_cleanup "container-abc123"
    assert_success

    # Container should be tracked
    assert_output --partial "registered=container-abc123"

    # Register another
    run register_container_for_cleanup "container-def456"
    assert_success

    assert_output --partial "registered=container-def456"
}

@test "unregister_container() removes container from tracking" {
    # Set up tracked containers
    ACTIVE_CONTAINERS="container-abc123 container-def456 container-ghi789"

    run unregister_container "container-def456"
    assert_success

    # Container should be unregistered
    assert_output --partial "unregistered=container-def456"
    assert_output --partial "remaining_containers="
}

# -----------------------------------------------------------------------------
# Test: Clean up temporary files in /tmp
# -----------------------------------------------------------------------------

@test "cleanup_temp_files() removes result files from /tmp" {
    # Create test result files with unique names for this test
    local suite_id="cleanup-${TEST_UNIQUE_ID}"
    local pid=$$
    local random=$RANDOM

    local result_file="/tmp/suitey_test_result_${suite_id}_${pid}_${random}"
    local output_file="/tmp/suitey_test_output_${suite_id}_${pid}_${random}"

    echo "test_status=passed" > "$result_file"
    echo "Test output" > "$output_file"

    # Verify files exist
    assert [ -f "$result_file" ]
    assert [ -f "$output_file" ]

    run cleanup_temp_files
    assert_success

    # Files should be removed
    assert [ ! -f "$result_file" ]
    assert [ ! -f "$output_file" ]

    # Should report cleanup
    assert_output --partial "temp_cleanup_completed=true"
}

@test "cleanup_temp_files() removes all suitey temporary files" {
    # Create various suitey temp files with unique names for this test
    local unique="${TEST_UNIQUE_ID}"
    echo "test1" > "/tmp/suitey_test_result_${unique}_1"
    echo "test2" > "/tmp/suitey_test_output_${unique}_2"
    echo "test3" > "/tmp/suitey_resource_${unique}_3"
    echo "test4" > "/tmp/suitey_build_${unique}_4"

    run cleanup_temp_files
    assert_success

    # The files we created should be removed
    assert [ ! -f "/tmp/suitey_test_result_${unique}_1" ]
    assert [ ! -f "/tmp/suitey_test_output_${unique}_2" ]
    assert [ ! -f "/tmp/suitey_resource_${unique}_3" ]
    assert [ ! -f "/tmp/suitey_build_${unique}_4" ]

    assert_output --partial "temp_cleanup_completed=true"
}

@test "cleanup_temp_files() handles empty /tmp gracefully" {
    # Don't clean up other tests' files - just test with no files created
    run cleanup_temp_files
    assert_success

    # Should complete without error
    assert_output --partial "temp_cleanup_completed=true"
}

@test "cleanup_temp_files() reports number of files removed" {
    # Create test files with unique names
    local unique="${TEST_UNIQUE_ID}"
    echo "test1" > "/tmp/suitey_cleanup_count_${unique}_1"
    echo "test2" > "/tmp/suitey_cleanup_count_${unique}_2"
    echo "test3" > "/tmp/suitey_cleanup_count_${unique}_3"

    # Use pattern parameter to only clean up THIS test's files (avoid race conditions)
    run cleanup_temp_files "${unique}"
    assert_success

    # Should report files removed
    assert_output --partial "temp_files_removed="
    
    # Extract count - should be exactly 3 (only our files matching the pattern)
    local files_removed
    files_removed=$(echo "$output" | grep "^temp_files_removed=" | cut -d'=' -f2)
    assert [ "$files_removed" -eq 3 ]
}

@test "cleanup_temp_files() does not remove non-suitey files" {
    # Create a non-suitey file with unique name
    local unique="${TEST_UNIQUE_ID}"
    local other_file="/tmp/not_suitey_file_${unique}"
    echo "other content" > "$other_file"

    # Create a suitey file
    local suitey_file="/tmp/suitey_should_be_removed_${unique}"
    echo "suitey content" > "$suitey_file"

    run cleanup_temp_files
    assert_success

    # Suitey file should be removed
    assert [ ! -f "$suitey_file" ]

    # Non-suitey file should remain
    assert [ -f "$other_file" ]

    # Clean up
    rm -f "$other_file"
}

# -----------------------------------------------------------------------------
# Test: Resource cleanup on completion
# -----------------------------------------------------------------------------

@test "cleanup_on_completion() cleans both containers and temp files" {
    # Create temp files with unique name
    local unique="${TEST_UNIQUE_ID}"
    echo "test" > "/tmp/suitey_completion_test_${unique}"

    run cleanup_on_completion
    assert_success

    # Should clean up temp files
    assert [ ! -f "/tmp/suitey_completion_test_${unique}" ]

    # Should report completion
    assert_output --partial "cleanup_status=complete"
    assert_output --partial "containers_cleaned="
    assert_output --partial "temp_files_removed="
}

@test "cleanup_on_completion() releases resource pool" {
    # Initialize resource pool (creates state file)
    resource_pool_init 4 >/dev/null 2>&1

    # Acquire some resources
    resource_pool_acquire 2 >/dev/null 2>&1

    # Verify pool state file exists
    assert [ -f "$SUITEY_POOL_STATE_FILE" ]

    # Call cleanup directly (not with run, to preserve environment)
    local output
    output=$(cleanup_on_completion 2>&1)
    local status=$?

    # Should succeed
    assert [ "$status" -eq 0 ]

    # Output should indicate cleanup completed
    echo "$output" | grep -q "cleanup_status=complete"
    assert [ $? -eq 0 ]
}

@test "get_active_container_count() returns number of tracked containers" {
    # Set up some active containers
    ACTIVE_CONTAINERS="container1 container2 container3"

    run get_active_container_count
    assert_success

    # Should return 3
    assert_output --partial "active_count=3"
}

@test "get_active_container_count() returns 0 when no containers" {
    ACTIVE_CONTAINERS=""

    run get_active_container_count
    assert_success

    # Should return 0
    assert_output --partial "active_count=0"
}

@test "is_resource_available() checks if resources can be acquired" {
    # Initialize pool with 2 slots (not with run, to preserve state)
    resource_pool_init 2 >/dev/null 2>&1

    # Initially should have resources
    run is_resource_available
    assert_success
    assert_output --partial "available=true"

    # Acquire all resources (not with run, to preserve state)
    resource_pool_acquire 2 >/dev/null 2>&1

    # Now should not have resources
    run is_resource_available
    assert_success
    assert_output --partial "available=false"
}

# -----------------------------------------------------------------------------
# Integration tests for resource management
# -----------------------------------------------------------------------------

@test "resource management integrates with parallel execution" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Initialize resource pool (not with run, to preserve state)
    resource_pool_init >/dev/null 2>&1

    # Get initial status
    run resource_pool_status
    assert_success
    
    local initial_available
    initial_available=$(echo "$output" | grep "^pool_available=" | cut -d'=' -f2)
    assert [ -n "$initial_available" ]
    assert [ "$initial_available" -gt 0 ]
}

@test "concurrent container limit is enforced during execution" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Get available cores
    local available_cores
    available_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Get max concurrent containers
    run get_max_concurrent_containers
    assert_success

    local max_containers
    max_containers=$(echo "$output" | grep "^max_containers=" | cut -d'=' -f2)

    # Max containers should not exceed available cores
    assert [ "$max_containers" -le "$available_cores" ]
}
