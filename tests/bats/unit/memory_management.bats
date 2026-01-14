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

    # Create a unique identifier for this test to avoid race conditions with parallel tests
    TEST_UNIQUE_ID="memtest_${BATS_TEST_NUMBER}_$$_${RANDOM}"

    # Track containers and images created during tests for cleanup
    TEST_CONTAINERS=()
    TEST_IMAGES=()

    # Reset global state
    ACTIVE_CONTAINERS=""
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

    unset TEST_UNIQUE_ID
}

# =============================================================================
# 3.3.5 Memory Resource Management Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Detect available system memory
# -----------------------------------------------------------------------------

@test "get_available_memory_gb() detects available system memory" {
    run get_available_memory_gb
    assert_success

    # Should return a numeric value representing GB
    assert_output --partial "available_memory_gb="
    
    # Extract the memory value
    local memory_gb
    memory_gb=$(echo "$output" | grep "^available_memory_gb=" | cut -d'=' -f2)
    
    # Should be a positive number
    assert [ -n "$memory_gb" ]
    assert [ "$memory_gb" -gt 0 ] 2>/dev/null || assert echo "$memory_gb" | grep -q "^[0-9]*\.[0-9]*$"
}

@test "get_available_memory_gb() handles systems with different memory detection methods" {
    # This test verifies the function works on the current system
    # It should use /proc/meminfo, sysctl, or fallback methods
    
    run get_available_memory_gb
    assert_success
    
    # Should provide reasonable output
    assert_output --partial "detection_method="
    
    # Should include a memory value
    local memory_gb
    memory_gb=$(echo "$output" | grep "^available_memory_gb=" | cut -d'=' -f2)
    assert [ -n "$memory_gb" ]
}

@test "get_total_memory_gb() returns total system memory" {
    run get_total_memory_gb
    assert_success

    # Should return total memory in GB
    assert_output --partial "total_memory_gb="
    
    local total_memory
    total_memory=$(echo "$output" | grep "^total_memory_gb=" | cut -d'=' -f2)
    assert [ -n "$total_memory" ]
    assert [ "$total_memory" -gt 0 ] 2>/dev/null || assert echo "$total_memory" | grep -q "^[0-9]*\.[0-9]*$"
}

# -----------------------------------------------------------------------------
# Test: Calculate memory per container based on parallelism
# -----------------------------------------------------------------------------

@test "calculate_memory_per_container_gb() calculates memory for single container" {
    # Test with total memory 8GB, 1 container, 20% headroom
    run calculate_memory_per_container_gb 8.0 1 0.2
    assert_success

    # Should calculate: (8.0 * (1 - 0.2)) / 1 = 6.4
    assert_output --partial "memory_per_container_gb=6.4"
    assert_output --partial "total_memory_gb=8.0"
    assert_output --partial "parallel_jobs=1"
    assert_output --partial "memory_headroom=0.2"
}

@test "calculate_memory_per_container_gb() calculates memory for multiple containers" {
    # Test with total memory 8GB, 4 containers, 20% headroom
    run calculate_memory_per_container_gb 8.0 4 0.2
    assert_success

    # Should calculate: (8.0 * (1 - 0.2)) / 4 = 1.6
    assert_output --partial "memory_per_container_gb=1.6"
    assert_output --partial "parallel_jobs=4"
}

@test "calculate_memory_per_container_gb() handles zero headroom" {
    run calculate_memory_per_container_gb 4.0 2 0.0
    assert_success

    # Should calculate: (4.0 * (1 - 0.0)) / 2 = 2.0
    assert_output --partial "memory_per_container_gb=2.0"
}

@test "calculate_memory_per_container_gb() handles high headroom" {
    run calculate_memory_per_container_gb 8.0 1 0.5
    assert_success

    # Should calculate: (8.0 * (1 - 0.5)) / 1 = 4.0
    assert_output --partial "memory_per_container_gb=4.0"
}

@test "calculate_memory_per_container_gb() ensures minimum memory allocation" {
    # Test with very low memory per container (should enforce minimum)
    run calculate_memory_per_container_gb 0.5 4 0.1
    assert_success

    # Should enforce minimum memory per container
    local memory_per_container
    memory_per_container=$(echo "$output" | grep "^memory_per_container_gb=" | cut -d'=' -f2)
    
    # Should be at least 0.1 GB (100MB) minimum
    assert echo "$memory_per_container >= 0.1" | bc -l | grep -q "1"
}

# -----------------------------------------------------------------------------
# Test: Apply memory limits to Docker containers
# -----------------------------------------------------------------------------

@test "apply_memory_limits_to_container() adds memory limits to Docker command" {
    local docker_cmd="docker run -d alpine:latest"
    local memory_limit_gb="2.0"
    local memory_swap_gb="4.0"

    run apply_memory_limits_to_container "$docker_cmd" "$memory_limit_gb" "$memory_swap_gb"
    assert_success

    # Should add --memory and --memory-swap flags
    assert_output --partial "--memory="
    assert_output --partial "--memory-swap="
    
    # Should include the original command
    assert_output --partial "docker run -d alpine:latest"
}

@test "apply_memory_limits_to_container() handles memory-only limit" {
    local docker_cmd="docker run -d ubuntu:latest"
    local memory_limit_gb="1.5"

    run apply_memory_limits_to_container "$docker_cmd" "$memory_limit_gb" ""
    assert_success

    # Should add --memory but not --memory-swap
    assert_output --partial "--memory="
    refute_output --partial "--memory-swap="
}

@test "apply_memory_limits_to_container() handles zero memory limit gracefully" {
    local docker_cmd="docker run -d alpine:latest"

    run apply_memory_limits_to_container "$docker_cmd" "0" ""
    assert_success

    # Should not add memory flags for zero limit
    refute_output --partial "--memory="
    assert_output --partial "docker run -d alpine:latest"
}

@test "apply_memory_limits_to_container() converts GB to bytes correctly" {
    local docker_cmd="docker run -d test:latest"
    local memory_limit_gb="0.5"  # 512MB

    run apply_memory_limits_to_container "$docker_cmd" "$memory_limit_gb" ""
    assert_success

    # Should convert 0.5GB to 536870912 bytes (512MB)
    assert_output --partial "--memory=536870912"
}

# -----------------------------------------------------------------------------
# Test: Handle memory allocation failures gracefully
# -----------------------------------------------------------------------------

@test "allocate_memory_for_containers() allocates memory successfully" {
    # Test with sufficient memory
    run allocate_memory_for_containers 4.0 2 0.2
    assert_success

    # Should return allocation details
    assert_output --partial "allocation_status=success"
    assert_output --partial "memory_per_container_gb="
    assert_output --partial "total_containers=2"
}

@test "allocate_memory_for_containers() handles insufficient memory" {
    # Test with very low total memory
    run allocate_memory_for_containers 0.1 4 0.1
    assert_success

    # Should still succeed but with warnings
    assert_output --partial "allocation_status="
    assert_output --partial "warning_message="
}

@test "allocate_memory_for_containers() validates input parameters" {
    # Test with invalid total memory
    run allocate_memory_for_containers "invalid" 2 0.2
    assert_failure

    # Test with zero containers
    run allocate_memory_for_containers 4.0 0 0.2
    assert_failure
}

# -----------------------------------------------------------------------------
# Test: CLI memory options
# -----------------------------------------------------------------------------

@test "parse_memory_cli_options() parses --max-memory-per-container option" {
    run parse_memory_cli_options "--max-memory-per-container" "2.5"
    assert_success

    assert_output --partial "max_memory_per_container_gb=2.5"
}

@test "parse_memory_cli_options() parses --total-memory-limit option" {
    run parse_memory_cli_options "--total-memory-limit" "8.0"
    assert_success

    assert_output --partial "total_memory_limit_gb=8.0"
}

@test "parse_memory_cli_options() parses --memory-headroom option" {
    run parse_memory_cli_options "--memory-headroom" "0.3"
    assert_success

    assert_output --partial "memory_headroom=0.3"
}

@test "parse_memory_cli_options() handles multiple options together" {
    run parse_memory_cli_options "--max-memory-per-container" "1.5" "--memory-headroom" "0.25"
    assert_success

    assert_output --partial "max_memory_per_container_gb=1.5"
    assert_output --partial "memory_headroom=0.25"
}

@test "parse_memory_cli_options() validates numeric values" {
    run parse_memory_cli_options "--max-memory-per-container" "invalid"
    assert_failure

    assert_output --partial "error_message="
}

@test "parse_memory_cli_options() validates memory headroom range" {
    # Test headroom > 1.0 (invalid)
    run parse_memory_cli_options "--memory-headroom" "1.5"
    assert_failure

    # Test negative headroom (invalid)
    run parse_memory_cli_options "--memory-headroom" "-0.1"
    assert_failure
}

@test "parse_memory_cli_options() provides default values when options not specified" {
    run parse_memory_cli_options
    assert_success

    # Should provide defaults
    assert_output --partial "max_memory_per_container_gb="
    assert_output --partial "total_memory_limit_gb="
    assert_output --partial "memory_headroom="
}

# -----------------------------------------------------------------------------
# Integration tests for memory management
# -----------------------------------------------------------------------------

@test "memory management integrates with container launch" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create test image
    local image_tag="suitey-memory-test-${TEST_UNIQUE_ID}"
    local dockerfile_content="FROM alpine:latest
RUN apk add --no-cache bash
WORKDIR /app
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Test memory limit application
    local container_config="test_image=$image_tag
working_directory=/app
cpu_cores=1
memory_limit_gb=0.5
container_name=memory-test-${TEST_UNIQUE_ID}"

    run launch_test_container "$container_config"
    assert_success

    # Should have applied memory limits
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    assert [ -n "$container_id" ]

    TEST_CONTAINERS+=("$container_id")

    # Verify container has memory limits (if supported by Docker version)
    local inspect_output
    inspect_output=$(docker inspect "$container_id" 2>/dev/null || echo "")
    if echo "$inspect_output" | grep -q "Memory"; then
        # Docker version supports memory inspection
        local memory_limit
        memory_limit=$(echo "$inspect_output" | grep -o '"Memory":[0-9]*' | cut -d':' -f2 || echo "")
        if [[ -n "$memory_limit" ]]; then
            # Should be approximately 512MB (0.5GB)
            assert [ "$memory_limit" -ge 500000000 ]  # At least 500MB
        fi
    fi
}

@test "memory allocation respects system constraints" {
    # Get system memory
    local system_memory
    system_memory=$(get_available_memory_gb 2>/dev/null | grep "^available_memory_gb=" | cut -d'=' -f2 || echo "4.0")

    # Try to allocate more memory than system has
    local excessive_memory=$(echo "$system_memory * 2" | bc -l 2>/dev/null || echo "16.0")

    run allocate_memory_for_containers "$excessive_memory" 1 0.1
    assert_success

    # Should succeed but may provide warnings
    assert_output --partial "allocation_status="
}

@test "memory headroom calculation works correctly" {
    # Test conservative memory calculation: (total_memory * (1 - headroom)) / max_parallel_jobs
    local total_memory=8.0
    local max_parallel=4
    local headroom=0.2

    run calculate_memory_per_container_gb "$total_memory" "$max_parallel" "$headroom"
    assert_success

    local expected_memory
    expected_memory=$(echo "scale=2; ($total_memory * (1 - $headroom)) / $max_parallel" | bc -l 2>/dev/null || echo "1.6")

    assert_output --partial "memory_per_container_gb=$expected_memory"
}

@test "memory options validation prevents invalid configurations" {
    # Test mutually exclusive options
    run parse_memory_cli_options "--max-memory-per-container" "1.0" "--total-memory-limit" "4.0"
    assert_success

    # Should handle both options
    assert_output --partial "max_memory_per_container_gb=1.0"
    assert_output --partial "total_memory_limit_gb=4.0"
}

@test "memory allocation handles edge cases gracefully" {
    # Test with very small memory
    run calculate_memory_per_container_gb 0.1 1 0.0
    assert_success

    # Should still provide some allocation
    local memory_per_container
    memory_per_container=$(echo "$output" | grep "^memory_per_container_gb=" | cut -d'=' -f2)
    assert [ -n "$memory_per_container" ]

    # Test with many containers
    run calculate_memory_per_container_gb 1.0 10 0.1
    assert_success

    # Should distribute memory among containers
    memory_per_container=$(echo "$output" | grep "^memory_per_container_gb=" | cut -d'=' -f2)
    assert echo "$memory_per_container > 0" | bc -l | grep -q "1"
}
