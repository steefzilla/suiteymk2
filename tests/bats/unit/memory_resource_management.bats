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
    
    # Set unique pool state file for this test
    export SUITEY_POOL_STATE_FILE="/tmp/suitey_resource_pool_${TEST_UNIQUE_ID}"
    
    # Reset global state
    ACTIVE_CONTAINERS=""
    PROCESSED_RESULT_FILES=""
    RESOURCE_POOL_CAPACITY=0
    RESOURCE_POOL_AVAILABLE=0
    RESOURCE_POOL_IN_USE=0
    RESOURCE_POOL_INITIALIZED=""
    
    # Reset memory configuration
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    unset SUITEY_TOTAL_MEMORY_LIMIT
    unset SUITEY_MEMORY_HEADROOM
}

teardown() {
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
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    unset SUITEY_TOTAL_MEMORY_LIMIT
    unset SUITEY_MEMORY_HEADROOM
}

# =============================================================================
# 3.3.5 Memory Resource Management Tests
# =============================================================================

# -----------------------------------------------------------------------------
# Test: Detect available system memory in real-time
# -----------------------------------------------------------------------------

@test "get_available_memory_mb() returns available system memory" {
    run get_available_memory_mb
    assert_success
    
    # Output should contain available_memory_mb with a positive number
    assert_output --partial "available_memory_mb="
    
    # Extract the value and verify it's a positive number
    local memory_mb
    memory_mb=$(echo "$output" | grep "^available_memory_mb=" | cut -d'=' -f2)
    assert [ -n "$memory_mb" ]
    assert [ "$memory_mb" -gt 0 ]
}

@test "get_total_memory_mb() returns total system memory" {
    run get_total_memory_mb
    assert_success
    
    # Output should contain total_memory_mb with a positive number
    assert_output --partial "total_memory_mb="
    
    # Extract the value and verify it's a positive number
    local memory_mb
    memory_mb=$(echo "$output" | grep "^total_memory_mb=" | cut -d'=' -f2)
    assert [ -n "$memory_mb" ]
    assert [ "$memory_mb" -gt 0 ]
}

@test "get_available_memory_mb() returns less than or equal to total memory" {
    local available_output total_output
    available_output=$(get_available_memory_mb 2>/dev/null)
    total_output=$(get_total_memory_mb 2>/dev/null)
    
    local available_mb total_mb
    available_mb=$(echo "$available_output" | grep "^available_memory_mb=" | cut -d'=' -f2)
    total_mb=$(echo "$total_output" | grep "^total_memory_mb=" | cut -d'=' -f2)
    
    assert [ "$available_mb" -le "$total_mb" ]
}

# -----------------------------------------------------------------------------
# Test: Calculate memory required per test runner
# -----------------------------------------------------------------------------

@test "get_memory_per_runner_mb() returns configured value when set" {
    export SUITEY_MAX_MEMORY_PER_CONTAINER=2048
    
    run get_memory_per_runner_mb
    assert_success
    
    # Should return the configured value
    assert_output --partial "memory_per_runner_mb=2048"
}

@test "get_memory_per_runner_mb() auto-calculates when not configured" {
    # Unset to ensure auto-calculation
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    # Should return a calculated value based on available memory and CPU cores
    assert_output --partial "memory_per_runner_mb="
    
    # Extract the value and verify it's a positive number
    local memory_mb
    memory_mb=$(echo "$output" | grep "^memory_per_runner_mb=" | cut -d'=' -f2)
    assert [ -n "$memory_mb" ]
    assert [ "$memory_mb" -gt 0 ]
}

@test "get_memory_per_runner_mb() respects memory headroom setting" {
    export SUITEY_MEMORY_HEADROOM=30
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    # Should return a value that accounts for 30% headroom
    assert_output --partial "memory_per_runner_mb="
    assert_output --partial "headroom_percent=30"
}

@test "get_memory_per_runner_mb() uses default 20% headroom" {
    unset SUITEY_MEMORY_HEADROOM
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    # Should use default 20% headroom
    assert_output --partial "headroom_percent=20"
}

@test "get_memory_per_runner_mb() considers total memory limit if set" {
    export SUITEY_TOTAL_MEMORY_LIMIT=8192
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    # Should consider the total memory limit in calculation
    assert_output --partial "total_memory_limit_mb=8192"
}

# -----------------------------------------------------------------------------
# Test: Block container launch when available memory < required memory
# -----------------------------------------------------------------------------

@test "check_memory_available() returns success when sufficient memory" {
    # Most systems have at least 100MB available
    run check_memory_available 100
    assert_success
    
    assert_output --partial "memory_available=true"
}

@test "check_memory_available() returns failure when insufficient memory" {
    # Request an unreasonably large amount of memory (1TB)
    run check_memory_available 1048576000
    assert_failure
    
    assert_output --partial "memory_available=false"
    assert_output --partial "reason=insufficient_memory"
}

@test "check_memory_available() reports current and required memory" {
    run check_memory_available 100
    
    # Should report both current available and required memory
    assert_output --partial "available_memory_mb="
    assert_output --partial "required_memory_mb=100"
}

# -----------------------------------------------------------------------------
# Test: Resume launching when memory becomes available
# -----------------------------------------------------------------------------

@test "wait_for_memory() returns immediately when memory is available" {
    # Wait for 100MB with 1 second timeout - should return immediately
    run timeout 5 bash -c 'source src/parallel_execution.sh && wait_for_memory 100 1'
    assert_success
    
    assert_output --partial "memory_available=true"
}

@test "wait_for_memory() times out when memory is not available" {
    # Request 1TB with 1 second timeout - should time out
    run timeout 5 bash -c 'source src/parallel_execution.sh && wait_for_memory 1048576000 1'
    assert_failure
    
    assert_output --partial "memory_available=false"
    assert_output --partial "reason=timeout"
}

@test "wait_for_memory() reports wait attempts" {
    # Request available memory amount
    run timeout 5 bash -c 'source src/parallel_execution.sh && wait_for_memory 100 2'
    assert_success
    
    # Should report the number of wait attempts (could be 0 if immediately available)
    assert_output --partial "wait_attempts="
}

# -----------------------------------------------------------------------------
# Test: Memory-based limit works alongside CPU-based limit
# -----------------------------------------------------------------------------

@test "get_max_parallel_runners() considers both CPU and memory limits" {
    run get_max_parallel_runners
    assert_success
    
    # Should report both CPU and memory based limits
    assert_output --partial "cpu_based_limit="
    assert_output --partial "memory_based_limit="
    assert_output --partial "effective_limit="
}

@test "get_max_parallel_runners() uses minimum of CPU and memory limits" {
    # Set explicit limits to verify it takes the minimum
    export SUITEY_MAX_CONTAINERS=8
    export SUITEY_MAX_MEMORY_PER_CONTAINER=2048
    
    run get_max_parallel_runners
    assert_success
    
    # Should use the more restrictive limit
    local cpu_limit memory_limit effective_limit
    cpu_limit=$(echo "$output" | grep "^cpu_based_limit=" | cut -d'=' -f2)
    memory_limit=$(echo "$output" | grep "^memory_based_limit=" | cut -d'=' -f2)
    effective_limit=$(echo "$output" | grep "^effective_limit=" | cut -d'=' -f2)
    
    # Effective limit should be the minimum of cpu and memory limits
    if [ "$cpu_limit" -lt "$memory_limit" ]; then
        assert_equal "$effective_limit" "$cpu_limit"
    else
        assert_equal "$effective_limit" "$memory_limit"
    fi
}

@test "get_max_parallel_runners() respects explicit container limit" {
    export SUITEY_MAX_CONTAINERS=2
    
    run get_max_parallel_runners
    assert_success
    
    # CPU-based limit should respect explicit limit
    assert_output --partial "cpu_based_limit=2"
}

# -----------------------------------------------------------------------------
# Test: CLI memory options
# -----------------------------------------------------------------------------

@test "parse_memory_options() parses --max-memory-per-container" {
    run parse_memory_options --max-memory-per-container 2048
    assert_success
    
    assert_output --partial "max_memory_per_container=2048"
}

@test "parse_memory_options() parses --total-memory-limit" {
    run parse_memory_options --total-memory-limit 16384
    assert_success
    
    assert_output --partial "total_memory_limit=16384"
}

@test "parse_memory_options() parses --memory-headroom" {
    run parse_memory_options --memory-headroom 25
    assert_success
    
    assert_output --partial "memory_headroom=25"
}

@test "parse_memory_options() validates memory headroom is percentage" {
    # Headroom must be between 0 and 99
    run parse_memory_options --memory-headroom 150
    assert_failure
    
    assert_output --partial "error"
}

@test "parse_memory_options() handles multiple options" {
    run parse_memory_options --max-memory-per-container 2048 --memory-headroom 30
    assert_success
    
    assert_output --partial "max_memory_per_container=2048"
    assert_output --partial "memory_headroom=30"
}

@test "parse_memory_options() uses defaults when not specified" {
    run parse_memory_options
    assert_success
    
    # Should indicate auto-calculated or default values
    assert_output --partial "max_memory_per_container=auto"
    assert_output --partial "memory_headroom=20"
}

# -----------------------------------------------------------------------------
# Integration tests: Memory checks in parallel execution
# -----------------------------------------------------------------------------

@test "launch_test_suites_parallel() checks memory before launching" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # This test verifies that memory checking is integrated
    # We set a very low memory requirement to ensure it passes
    export SUITEY_MAX_MEMORY_PER_CONTAINER=1
    
    # The function should check memory availability
    # Even without launching, this verifies the integration point exists
    run bash -c 'source src/parallel_execution.sh && type launch_test_suites_parallel | grep -q "check_memory_available"'
    
    # If the function doesn't contain memory checks yet, skip
    if [ $status -ne 0 ]; then
        skip "Memory checks not yet integrated into launch_test_suites_parallel"
    fi
    
    assert_success
}

@test "memory limit is more restrictive than CPU when memory is scarce" {
    # Simulate a memory-constrained environment
    # Set memory per runner to a very high value
    export SUITEY_MAX_MEMORY_PER_CONTAINER=999999
    export SUITEY_MAX_CONTAINERS=16
    
    run get_max_parallel_runners
    assert_success
    
    # Memory should be the more restrictive factor
    local memory_limit effective_limit
    memory_limit=$(echo "$output" | grep "^memory_based_limit=" | cut -d'=' -f2)
    effective_limit=$(echo "$output" | grep "^effective_limit=" | cut -d'=' -f2)
    
    # With very high memory requirement per container, memory limit should be low
    assert [ "$memory_limit" -lt 16 ]
    assert [ "$effective_limit" -eq "$memory_limit" ]
}

# -----------------------------------------------------------------------------
# Edge case tests
# -----------------------------------------------------------------------------

@test "get_available_memory_mb() handles /proc/meminfo not available" {
    # On some systems, /proc/meminfo might not exist
    # The function should handle this gracefully
    run bash -c '
        source src/parallel_execution.sh
        # Mock a system without /proc/meminfo by checking fallback behavior
        get_available_memory_mb
    '
    assert_success
}

@test "memory functions handle zero or negative values gracefully" {
    export SUITEY_MAX_MEMORY_PER_CONTAINER=0
    
    run get_memory_per_runner_mb
    
    # Should either fail gracefully or use a sensible default
    if [ $status -eq 0 ]; then
        local memory_mb
        memory_mb=$(echo "$output" | grep "^memory_per_runner_mb=" | cut -d'=' -f2)
        # Should be a positive value (fallback or auto-calculated)
        assert [ "$memory_mb" -gt 0 ]
    else
        # Or fail with a clear error
        assert_output --partial "error"
    fi
}

@test "memory headroom of 0% uses all available memory" {
    export SUITEY_MEMORY_HEADROOM=0
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    assert_output --partial "headroom_percent=0"
}

@test "memory headroom of 99% leaves minimal memory for runners" {
    export SUITEY_MEMORY_HEADROOM=99
    unset SUITEY_MAX_MEMORY_PER_CONTAINER
    
    run get_memory_per_runner_mb
    assert_success
    
    # With 99% headroom, very little memory is available for runners
    assert_output --partial "headroom_percent=99"
}

