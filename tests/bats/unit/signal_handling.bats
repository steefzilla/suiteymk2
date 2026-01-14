#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source required modules
    if [[ -f "src/execution_system.sh" ]]; then
        source "src/execution_system.sh"
    fi

    if [[ -f "src/build_manager.sh" ]]; then
        source "src/build_manager.sh"
    fi

    if [[ -f "src/parallel_execution.sh" ]]; then
        source "src/parallel_execution.sh"
    fi

    # Create unique identifier for this test to avoid race conditions with parallel tests
    TEST_UNIQUE_ID="signal_${BATS_TEST_NUMBER}_$$_${RANDOM}"

    # Track containers and images created during tests for cleanup
    TEST_CONTAINERS=()
    TEST_IMAGES=()

    # Reset signal handling state
    SIGNAL_RECEIVED=""
    FORCE_KILL_TRIGGERED=""
}

teardown() {
    # Clean up containers
    for container_id in "${TEST_CONTAINERS[@]}"; do
        if [[ -n "$container_id" ]]; then
            cleanup_test_container "$container_id" >/dev/null 2>&1 || true
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

    # Reset signal state
    SIGNAL_RECEIVED=""
    FORCE_KILL_TRIGGERED=""
    
    unset TEST_UNIQUE_ID
}

@test "setup_signal_handlers() sets up SIGINT handler" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Setup signal handlers
    run setup_signal_handlers
    assert_success

    # Should set up signal handler (we can't easily test actual signal handling in unit tests)
    # But we can verify the function exists and runs without error
    assert_output --partial "signal_handlers_setup=success"
}

@test "handle_sigint() terminates containers gracefully on first SIGINT" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create test containers to terminate
    local image_tag="suitey-signal-test-$$"
    local dockerfile_content="FROM alpine:latest
RUN apk add --no-cache bash
CMD sleep 300"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Start test containers
    local container1
    container1=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')
    local container2
    container2=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')

    if [[ -z "$container1" ]] || [[ -z "$container2" ]]; then
        skip "Failed to create test containers"
    fi

    TEST_CONTAINERS+=("$container1" "$container2")

    # Set up global container tracking
    ACTIVE_CONTAINERS="$container1 $container2"

    # Handle first SIGINT
    run handle_sigint
    assert_success

    # Should mark signal as received
    assert_output --partial "signal_received=first"
    assert_output --partial "graceful_termination=initiated"

    # Should NOT trigger force kill on first signal
    refute_output --partial "force_kill=triggered"
}

@test "handle_sigint() force kills containers on second SIGINT" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create test containers
    local image_tag="suitey-signal-force-$$"
    local dockerfile_content="FROM alpine:latest
RUN apk add --no-cache bash
CMD sleep 300"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Start test containers
    local container1
    container1=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')
    local container2
    container2=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')

    if [[ -z "$container1" ]] || [[ -z "$container2" ]]; then
        skip "Failed to create test containers"
    fi

    TEST_CONTAINERS+=("$container1" "$container2")

    # Set up global state - simulate first SIGINT already received
    SIGNAL_RECEIVED="first"
    ACTIVE_CONTAINERS="$container1 $container2"

    # Handle second SIGINT
    run handle_sigint
    assert_success

    # Should trigger force kill on second signal
    assert_output --partial "signal_received=second"
    assert_output --partial "force_kill=triggered"
    assert_output --partial "immediate_termination=initiated"
}

@test "cleanup_containers() removes all tracked containers" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create test containers
    local image_tag="suitey-cleanup-test-$$"
    local dockerfile_content="FROM alpine:latest
RUN apk add --no-cache bash
CMD sleep 300"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Start test containers
    local container1
    container1=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')
    local container2
    container2=$(docker run -d "$image_tag" 2>/dev/null | tr -d '\n')

    if [[ -z "$container1" ]] || [[ -z "$container2" ]]; then
        skip "Failed to create test containers"
    fi

    TEST_CONTAINERS+=("$container1" "$container2")

    # Set up global container tracking
    ACTIVE_CONTAINERS="$container1 $container2"

    # Clean up containers
    run cleanup_containers
    assert_success

    # Should report successful cleanup
    assert_output --partial "cleanup_completed=true"
    assert_output --partial "containers_cleaned=2"

    # Verify containers are actually removed (they should be gone or stopping)
    # Note: Containers might still be in "stopping" state, so we check they're not running
    local running_containers
    running_containers=$(docker ps --filter "id=$container1" --filter "id=$container2" --format "{{.ID}}" | wc -l)
    assert [ "$running_containers" -eq 0 ]
}

@test "cleanup_temp_files() removes temporary files from /tmp" {
    # Create temporary test files with unique ID to avoid parallel test conflicts
    local temp_file1="/tmp/suitey_test_result_${TEST_UNIQUE_ID}_1"
    local temp_file2="/tmp/suitey_test_output_${TEST_UNIQUE_ID}_2"
    local temp_file3="/tmp/suitey_other_temp_${TEST_UNIQUE_ID}_3"

    # Create the files
    echo "test result 1" > "$temp_file1"
    echo "test output 1" > "$temp_file2"
    echo "other temp file" > "$temp_file3"

    # Verify files exist
    assert [ -f "$temp_file1" ]
    assert [ -f "$temp_file2" ]
    assert [ -f "$temp_file3" ]

    # Clean up temporary files (using pattern to only clean up THIS test's files)
    run cleanup_temp_files "${TEST_UNIQUE_ID}"
    assert_success

    # Should report successful cleanup
    assert_output --partial "temp_cleanup_completed=true"

    # Files should be removed
    assert [ ! -f "$temp_file1" ]
    assert [ ! -f "$temp_file2" ]
    assert [ ! -f "$temp_file3" ]
}

@test "signal_handler_integration() coordinates signal handling workflow" {
    # This test verifies the complete signal handling workflow
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Test that signal handler functions exist and can be called
    # (Full integration testing of signals is difficult in unit tests)

    # Setup should work
    run setup_signal_handlers
    assert_success
    assert_output --partial "signal_handlers_setup=success"

    # Cleanup functions should work
    run cleanup_containers
    assert_success
    assert_output --partial "cleanup_completed=true"

    run cleanup_temp_files
    assert_success
    assert_output --partial "temp_cleanup_completed=true"
}

@test "handle_sigint() handles empty container list gracefully" {
    # Test with no active containers
    ACTIVE_CONTAINERS=""

    # Handle SIGINT with no containers
    run handle_sigint
    assert_success

    # Should still report signal handling
    assert_output --partial "signal_received=first"
    assert_output --partial "graceful_termination=initiated"
    assert_output --partial "active_containers=0"
}

@test "cleanup_containers() handles empty container list gracefully" {
    # Test cleanup with no containers
    ACTIVE_CONTAINERS=""

    run cleanup_containers
    assert_success

    # Should report zero containers cleaned
    assert_output --partial "containers_cleaned=0"
    assert_output --partial "cleanup_completed=true"
}

@test "cleanup_containers() handles invalid container IDs gracefully" {
    # Test cleanup with invalid container IDs
    ACTIVE_CONTAINERS="invalid-id-1 invalid-id-2 nonexistent-container"

    run cleanup_containers
    assert_success

    # Should attempt cleanup but not fail on invalid IDs
    assert_output --partial "cleanup_completed=true"
    # May or may not clean any containers, but shouldn't crash
}

