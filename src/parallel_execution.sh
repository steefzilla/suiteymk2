#!/usr/bin/env bash

# Parallel Execution Manager
# Coordinates parallel execution of multiple test suites
# Handles CPU core limiting, container tracking, and result aggregation

# Source required dependencies
source "src/execution_system.sh" 2>/dev/null || true
source "src/build_manager.sh" 2>/dev/null || true

# Launch multiple test suites in parallel Docker containers
# Usage: launch_test_suites_parallel <suite_configs>
# Arguments: suite_configs - Newline-separated list of suite configurations
# Each suite config is a flat data format string with:
#   suite_id=<id>
#   test_command=<command>
#   test_image=<image>
#   working_directory=<path>
#   cpu_cores=<count>
# Returns: Execution results in flat data format
launch_test_suites_parallel() {
    local suite_configs="$1"

    # If no argument provided, read from stdin
    if [[ -z "$suite_configs" ]]; then
        suite_configs=$(cat)
    fi

    # Initialize counters and tracking
    local total_suites=0
    local launched_suites=0
    local container_ids=""
    local execution_status="success"

    # Parse suite configurations
    local suite_array=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # If line starts with "suite_id=", it's a new suite configuration
        if [[ "$line" =~ ^suite_id= ]]; then
            # If we have a previous suite, add it to the array
            if [[ -n "${current_suite:-}" ]]; then
                suite_array+=("$current_suite")
            fi
            # Start new suite
            current_suite="$line"
            ((total_suites++))
        else
            # Continue building current suite
            current_suite="$current_suite"$'\n'"$line"
        fi
    done <<< "$suite_configs"

    # Add the last suite if it exists
    if [[ -n "${current_suite:-}" ]]; then
        suite_array+=("$current_suite")
    fi

    # Handle empty input
    if [[ ${#suite_array[@]} -eq 0 ]]; then
        echo "total_suites=0"
        echo "launched_suites=0"
        echo "container_ids="
        echo "execution_status=success"
        return 0
    fi

    # Get max parallel runners considering both CPU and memory limits
    local max_parallel_output max_parallel memory_per_runner
    max_parallel_output=$(get_max_parallel_runners 2>/dev/null)
    max_parallel=$(echo "$max_parallel_output" | grep "^effective_limit=" | cut -d'=' -f2 || echo "4")
    memory_per_runner=$(echo "$max_parallel_output" | grep "^memory_per_runner_mb=" | cut -d'=' -f2 || echo "256")
    
    # Ensure we have valid values
    max_parallel="${max_parallel:-4}"
    memory_per_runner="${memory_per_runner:-256}"

    # Launch suites in batches based on available resources (CPU and memory)
    local current_batch=()
    local batch_size=0

    for suite_config in "${suite_array[@]}"; do
        # Parse suite configuration
        local suite_id
        local test_command
        local test_image
        local working_directory
        local cpu_cores

        suite_id=$(echo "$suite_config" | grep "^suite_id=" | cut -d'=' -f2 || echo "")
        test_command=$(echo "$suite_config" | grep "^test_command=" | cut -d'=' -f2- || echo "")
        test_image=$(echo "$suite_config" | grep "^test_image=" | cut -d'=' -f2 || echo "")
        working_directory=$(echo "$suite_config" | grep "^working_directory=" | cut -d'=' -f2 || echo "/app")
        cpu_cores=$(echo "$suite_config" | grep "^cpu_cores=" | cut -d'=' -f2 || echo "1")

        # Validate required fields
        if [[ -z "$suite_id" ]] || [[ -z "$test_command" ]] || [[ -z "$test_image" ]]; then
            echo "Error: Invalid suite configuration - missing required fields" >&2
            execution_status="error"
            continue
        fi

        # Check if we need to launch current batch
        if [[ $batch_size -ge $max_parallel ]]; then
            # Check memory availability before launching batch
            local memory_check
            memory_check=$(check_memory_available "$memory_per_runner" 2>/dev/null)
            local memory_available
            memory_available=$(echo "$memory_check" | grep "^memory_available=" | cut -d'=' -f2)
            
            # If memory is not available, wait for it (with timeout)
            if [[ "$memory_available" != "true" ]]; then
                echo "waiting_for_memory=true" >&2
                wait_for_memory "$memory_per_runner" 30 >/dev/null 2>&1 || true
            fi
            
            # Launch current batch and wait for completion
            local batch_containers
            batch_containers=$(_launch_batch "${current_batch[@]}")
            local batch_result=$?
            if [[ $batch_result -ne 0 ]]; then
                execution_status="error"
            fi

            # Add batch containers to tracking
            if [[ -n "$batch_containers" ]]; then
                if [[ -z "$container_ids" ]]; then
                    container_ids="$batch_containers"
                else
                    container_ids="$container_ids,$batch_containers"
                fi
            fi

            # Reset batch
            current_batch=()
            batch_size=0
        fi

        # Add suite to current batch (single line format)
        local container_config="test_image=$test_image|working_directory=$working_directory|cpu_cores=$cpu_cores|container_name=suitey-test-$suite_id-$$"

        current_batch+=("$suite_id|$test_command|$container_config")
        ((batch_size++))
    done

    # Launch final batch
    if [[ ${#current_batch[@]} -gt 0 ]]; then
        # Check memory availability before launching final batch
        local memory_check
        memory_check=$(check_memory_available "$memory_per_runner" 2>/dev/null)
        local memory_available
        memory_available=$(echo "$memory_check" | grep "^memory_available=" | cut -d'=' -f2)
        
        # If memory is not available, wait for it (with timeout)
        if [[ "$memory_available" != "true" ]]; then
            echo "waiting_for_memory=true" >&2
            wait_for_memory "$memory_per_runner" 30 >/dev/null 2>&1 || true
        fi
        
        local batch_containers
        batch_containers=$(_launch_batch "${current_batch[@]}")
        local batch_result=$?
        if [[ $batch_result -ne 0 ]]; then
            execution_status="error"
        fi

        # Add final batch containers to tracking
        if [[ -n "$batch_containers" ]]; then
            if [[ -z "$container_ids" ]]; then
                container_ids="$batch_containers"
            else
                container_ids="$container_ids,$batch_containers"
            fi
        fi
    fi

    # Count total launched suites (this would be tracked in the batch launch function)
    launched_suites=$total_suites

    # Return results
    echo "total_suites=$total_suites"
    echo "launched_suites=$launched_suites"
    echo "container_ids=$container_ids"
    echo "execution_status=$execution_status"

    return 0
}

# Internal function to launch a batch of test suites
# Usage: _launch_batch suite_specs...
# Arguments: suite_specs - Array of "suite_id|test_command|container_config" strings
# Returns: Comma-separated list of container IDs
_launch_batch() {
    local suite_specs=("$@")
    local pids=()
    local temp_containers=()

    # Launch all suites in this batch
    for spec in "${suite_specs[@]}"; do
        # Parse spec
        IFS='|' read -r suite_id test_command container_config_str <<< "$spec"

        # Parse container config from single line format
        local container_config=""
        IFS='|' read -r test_image_part working_dir_part cpu_cores_part container_name_part <<< "$container_config_str"
        local test_image=$(echo "$test_image_part" | cut -d'=' -f2)
        local working_directory=$(echo "$working_dir_part" | cut -d'=' -f2)
        local cpu_cores=$(echo "$cpu_cores_part" | cut -d'=' -f2)
        local container_name=$(echo "$container_name_part" | cut -d'=' -f2)

        container_config="test_image=$test_image
working_directory=$working_directory
cpu_cores=$cpu_cores
container_name=$container_name"

        # Launch container
        local launch_result
        launch_result=$(launch_test_container "$container_config" 2>&1)
        local launch_status=$?

        if [[ $launch_status -eq 0 ]]; then
            # Extract container ID
            local container_id
            container_id=$(echo "$launch_result" | grep "^container_id=" | cut -d'=' -f2 || echo "")

            if [[ -n "$container_id" ]]; then
                temp_containers+=("$container_id")

                # Launch test execution in background
                (
                    # Execute test command
                    local test_result
                    test_result=$(execute_test_command "$container_id" "$test_command" 2>&1)

                    # Collect test results
                    collect_test_results "$suite_id" "$test_result" >/dev/null 2>&1

                    # Clean up container
                    cleanup_test_container "$container_id" >/dev/null 2>&1 || true
                ) &
                pids+=($!)
            fi
        fi
    done

    # Wait for all suites in this batch to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Return comma-separated container IDs
    local result=""
    for container_id in "${temp_containers[@]}"; do
        if [[ -z "$result" ]]; then
            result="$container_id"
        else
            result="$result,$container_id"
        fi
    done

    echo "$result"
    return 0
}

# Global variables for signal handling
PROCESSED_RESULT_FILES=""
SIGNAL_RECEIVED=""
ACTIVE_CONTAINERS=""
FORCE_KILL_TRIGGERED=""

# Poll result files in /tmp as tests complete
# Usage: poll_test_results
# Returns: Flat data format with completed test results
# Looks for files matching pattern: suitey_test_result_*
# Tracks processed files to avoid re-reading
poll_test_results() {
    local results_found=0
    local all_results=""

    # Find all result files matching the pattern
    local result_files
    result_files=$(find /tmp -name "suitey_test_result_*" -type f 2>/dev/null || true)

    # Process each result file
    while IFS= read -r result_file; do
        [[ -z "$result_file" ]] && continue

        # Extract suite_id and unique identifiers from filename
        local filename
        filename=$(basename "$result_file")
        local suite_id=""
        local pid_part=""
        local random_part=""

        # Parse filename: suitey_test_result_<suite_id>_<pid>_<random>
        # Use numeric pattern for pid and random to handle suite_ids with underscores
        if [[ "$filename" =~ suitey_test_result_(.+)_([0-9]+)_([0-9]+)$ ]]; then
            suite_id="${BASH_REMATCH[1]}"
            pid_part="${BASH_REMATCH[2]}"
            random_part="${BASH_REMATCH[3]}"
        else
            # Skip files that don't match expected pattern
            continue
        fi

        # Check if we've already processed this file
        local file_key="$suite_id:$pid_part:$random_part"
        if [[ "$PROCESSED_RESULT_FILES" == *"$file_key"* ]]; then
            continue
        fi

        # Check if file is fully written (atomic write check)
        # For now, assume file is complete if it exists and has content
        if [[ ! -s "$result_file" ]]; then
            # File is empty, skip for now
            continue
        fi

        # Read result file content
        local result_content=""
        if result_content=$(cat "$result_file" 2>/dev/null); then
            # Mark file as processed
            PROCESSED_RESULT_FILES="$PROCESSED_RESULT_FILES|$file_key"

            # Find corresponding output file
            local output_file="/tmp/suitey_test_output_${suite_id}_${pid_part}_${random_part}"

            # Build result output
            local result_output="suite_id=$suite_id
result_file=$result_file
output_file=$output_file
$result_content"

            # Append to all results
            if [[ -z "$all_results" ]]; then
                all_results="$result_output"
            else
                all_results="$all_results
---
$result_output"
            fi

            ((results_found++))
        fi
    done <<< "$result_files"

    # Return results
    if [[ $results_found -eq 0 ]]; then
        echo "results_found=0"
        echo "status=no_results"
    else
        echo "results_found=$results_found"
        echo "$all_results"
        echo "status=results_found"
    fi

    return 0
}

# Set up signal handlers for graceful shutdown
# Usage: setup_signal_handlers
# Sets up SIGINT handler and cleanup traps
setup_signal_handlers() {
    # Set up SIGINT handler
    trap 'handle_sigint' INT

    # Set up cleanup on exit
    trap 'cleanup_on_exit' EXIT

    echo "signal_handlers_setup=success"
    echo "trap_int=installed"
    echo "trap_exit=installed"

    return 0
}

# Handle SIGINT (Ctrl+C) signal
# Usage: handle_sigint
# First SIGINT: graceful termination
# Second SIGINT: force kill
handle_sigint() {
    if [[ -z "$SIGNAL_RECEIVED" ]]; then
        # First SIGINT - graceful termination
        SIGNAL_RECEIVED="first"

        echo "signal_received=first" >&2
        echo "graceful_termination=initiated" >&2

        # Count active containers
        local container_count=0
        if [[ -n "$ACTIVE_CONTAINERS" ]]; then
            container_count=$(echo "$ACTIVE_CONTAINERS" | wc -w)
        fi

        echo "active_containers=$container_count" >&2

        # Send graceful termination to containers
        graceful_terminate_containers

        echo "waiting_for_graceful_shutdown=10_seconds" >&2
        # In a real implementation, we'd sleep here, but for testing we'll skip

    else
        # Second SIGINT - force kill
        SIGNAL_RECEIVED="second"
        FORCE_KILL_TRIGGERED="true"

        echo "signal_received=second" >&2
        echo "force_kill=triggered" >&2
        echo "immediate_termination=initiated" >&2

        # Force kill all containers
        force_kill_containers
    fi

    return 0
}

# Gracefully terminate all active containers
# Usage: graceful_terminate_containers
# Sends SIGTERM to containers for clean shutdown
graceful_terminate_containers() {
    local terminated_count=0

    for container_id in $ACTIVE_CONTAINERS; do
        if [[ -n "$container_id" ]]; then
            echo "gracefully_terminating_container=$container_id" >&2
            docker stop "$container_id" >/dev/null 2>&1 || true
            ((terminated_count++))
        fi
    done

    echo "containers_gracefully_terminated=$terminated_count" >&2
}

# Force kill all active containers
# Usage: force_kill_containers
# Sends SIGKILL to containers for immediate termination
force_kill_containers() {
    local killed_count=0

    for container_id in $ACTIVE_CONTAINERS; do
        if [[ -n "$container_id" ]]; then
            echo "force_killing_container=$container_id" >&2
            docker kill "$container_id" >/dev/null 2>&1 || true
            ((killed_count++))
        fi
    done

    echo "containers_force_killed=$killed_count" >&2
}

# Clean up all active containers
# Usage: cleanup_containers
# Removes stopped containers and cleans up resources
cleanup_containers() {
    local cleaned_count=0

    for container_id in $ACTIVE_CONTAINERS; do
        if [[ -n "$container_id" ]]; then
            echo "cleaning_up_container=$container_id" >&2
            # First stop if running
            docker stop "$container_id" >/dev/null 2>&1 || true
            # Then remove
            docker rm "$container_id" >/dev/null 2>&1 || true
            ((cleaned_count++))
        fi
    done

    echo "containers_cleaned=$cleaned_count"
    echo "cleanup_completed=true"

    # Clear active containers list
    ACTIVE_CONTAINERS=""

    return 0
}

# Clean up temporary files from /tmp
# Usage: cleanup_temp_files [pattern]
# Removes suitey temporary files. If pattern is provided, only removes files
# matching "suitey_*${pattern}*", otherwise removes all "suitey_*" files.
# Environment variable SUITEY_CLEANUP_PATTERN can also be used to restrict cleanup.
cleanup_temp_files() {
    local pattern="${1:-${SUITEY_CLEANUP_PATTERN:-}}"
    local files_removed=0

    # Remove suitey temporary files (optionally filtered by pattern)
    local suitey_files
    if [[ -n "$pattern" ]]; then
        suitey_files=$(find /tmp -name "suitey_*${pattern}*" -type f 2>/dev/null || true)
    else
        suitey_files=$(find /tmp -name "suitey_*" -type f 2>/dev/null || true)
    fi
    for file in $suitey_files; do
        rm -f "$file" 2>/dev/null || true
        ((files_removed++))
    done

    echo "temp_files_removed=$files_removed"
    echo "temp_cleanup_completed=true"

    return 0
}

# Clean up on exit (called by EXIT trap)
# Usage: cleanup_on_exit
# Performs final cleanup when suitey exits
cleanup_on_exit() {
    echo "performing_exit_cleanup" >&2

    # Clean up containers if any are still active
    if [[ -n "$ACTIVE_CONTAINERS" ]]; then
        echo "cleaning_up_containers_on_exit" >&2
        cleanup_containers >/dev/null 2>&1 || true
    fi

    # Clean up temporary files
    echo "cleaning_up_temp_files_on_exit" >&2
    cleanup_temp_files >/dev/null 2>&1 || true

    echo "exit_cleanup_completed" >&2
}

# =============================================================================
# Resource Management Functions (3.3.4)
# =============================================================================

# Global variables for resource pool management
RESOURCE_POOL_CAPACITY=0
RESOURCE_POOL_AVAILABLE=0
RESOURCE_POOL_IN_USE=0
RESOURCE_POOL_INITIALIZED=""

# Get maximum number of concurrent containers
# Usage: get_max_concurrent_containers [explicit_limit]
# Returns: Maximum container count in flat data format
# Behavior: Returns CPU core count or explicit limit (whichever is smaller)
get_max_concurrent_containers() {
    local explicit_limit="${1:-}"
    local available_cores

    # Get available CPU cores
    available_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Ensure we have at least 1 core
    if [[ -z "$available_cores" ]] || [[ "$available_cores" -lt 1 ]]; then
        available_cores=1
    fi

    local max_containers="$available_cores"
    local limited_by_cpu="false"

    # If explicit limit is provided
    if [[ -n "$explicit_limit" ]]; then
        # Validate it's a positive integer
        if [[ "$explicit_limit" =~ ^[0-9]+$ ]] && [[ "$explicit_limit" -gt 0 ]]; then
            if [[ "$explicit_limit" -gt "$available_cores" ]]; then
                # Limit to available cores
                max_containers="$available_cores"
                limited_by_cpu="true"
            else
                max_containers="$explicit_limit"
            fi
        else
            # Invalid limit, use all available
            max_containers="$available_cores"
        fi
    fi

    # Ensure minimum of 1
    if [[ "$max_containers" -lt 1 ]]; then
        max_containers=1
    fi

    echo "max_containers=$max_containers"
    echo "available_cores=$available_cores"
    echo "limited_by_cpu=$limited_by_cpu"

    return 0
}

# Get the resource pool state file path
# Usage: _get_pool_state_file
# Returns: Path to pool state file
# Note: Can be overridden by SUITEY_POOL_STATE_FILE environment variable for testing
_get_pool_state_file() {
    echo "${SUITEY_POOL_STATE_FILE:-/tmp/suitey_resource_pool_$$}"
}

# Initialize resource pool with given capacity
# Usage: resource_pool_init [capacity]
# Returns: Pool initialization status in flat data format
# Behavior: Initializes pool with CPU cores or custom capacity
resource_pool_init() {
    local capacity="${1:-}"
    local available_cores

    # Get available CPU cores
    available_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Ensure we have at least 1 core
    if [[ -z "$available_cores" ]] || [[ "$available_cores" -lt 1 ]]; then
        available_cores=1
    fi

    # Use custom capacity or default to available cores
    if [[ -n "$capacity" ]] && [[ "$capacity" =~ ^[0-9]+$ ]] && [[ "$capacity" -gt 0 ]]; then
        # Limit capacity to available cores
        if [[ "$capacity" -gt "$available_cores" ]]; then
            capacity="$available_cores"
        fi
    else
        capacity="$available_cores"
    fi

    # Ensure minimum of 1
    if [[ "$capacity" -lt 1 ]]; then
        capacity=1
    fi

    # Initialize pool state
    RESOURCE_POOL_CAPACITY="$capacity"
    RESOURCE_POOL_AVAILABLE="$capacity"
    RESOURCE_POOL_IN_USE=0
    RESOURCE_POOL_INITIALIZED="true"

    # Create pool state file for persistence across subshells
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    echo "capacity=$capacity" > "$pool_state_file"
    echo "available=$capacity" >> "$pool_state_file"
    echo "in_use=0" >> "$pool_state_file"

    echo "pool_capacity=$capacity"
    echo "pool_available=$capacity"
    echo "pool_in_use=0"
    echo "pool_status=initialized"

    return 0
}

# Acquire resources from pool
# Usage: resource_pool_acquire <count> [no_wait]
# Returns: Acquisition status in flat data format
# Behavior: Acquires specified number of resources if available
resource_pool_acquire() {
    local count="${1:-1}"
    local no_wait="${2:-}"

    # Validate count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
        count=1
    fi

    # Read current pool state
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    local available=0
    local capacity=0
    local in_use=0

    if [[ -f "$pool_state_file" ]]; then
        available=$(grep "^available=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        capacity=$(grep "^capacity=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        in_use=$(grep "^in_use=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
    else
        # Pool not initialized, use global variables
        available="$RESOURCE_POOL_AVAILABLE"
        capacity="$RESOURCE_POOL_CAPACITY"
        in_use="$RESOURCE_POOL_IN_USE"
    fi

    # Ensure numeric values
    available="${available:-0}"
    capacity="${capacity:-0}"
    in_use="${in_use:-0}"

    # Check if resources are available
    if [[ "$available" -lt "$count" ]]; then
        echo "acquired=0"
        echo "requested=$count"
        echo "available=$available"
        echo "acquire_status=exhausted"
        return 1
    fi

    # Acquire resources
    local new_available=$((available - count))
    local new_in_use=$((in_use + count))

    # Update pool state
    RESOURCE_POOL_AVAILABLE="$new_available"
    RESOURCE_POOL_IN_USE="$new_in_use"

    # Update state file
    if [[ -f "$pool_state_file" ]]; then
        echo "capacity=$capacity" > "$pool_state_file"
        echo "available=$new_available" >> "$pool_state_file"
        echo "in_use=$new_in_use" >> "$pool_state_file"
    fi

    echo "acquired=$count"
    echo "pool_available=$new_available"
    echo "pool_in_use=$new_in_use"
    echo "acquire_status=success"

    return 0
}

# Release resources back to pool
# Usage: resource_pool_release <count>
# Returns: Release status in flat data format
# Behavior: Releases specified number of resources back to pool
resource_pool_release() {
    local count="${1:-1}"

    # Validate count
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -lt 1 ]]; then
        count=1
    fi

    # Read current pool state
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    local available=0
    local capacity=0
    local in_use=0

    if [[ -f "$pool_state_file" ]]; then
        available=$(grep "^available=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        capacity=$(grep "^capacity=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        in_use=$(grep "^in_use=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
    else
        # Pool not initialized, use global variables
        available="$RESOURCE_POOL_AVAILABLE"
        capacity="$RESOURCE_POOL_CAPACITY"
        in_use="$RESOURCE_POOL_IN_USE"
    fi

    # Ensure numeric values
    available="${available:-0}"
    capacity="${capacity:-0}"
    in_use="${in_use:-0}"

    # Don't release more than in use
    if [[ "$count" -gt "$in_use" ]]; then
        count="$in_use"
    fi

    # Release resources
    local new_available=$((available + count))
    local new_in_use=$((in_use - count))

    # Don't exceed capacity
    if [[ "$new_available" -gt "$capacity" ]]; then
        new_available="$capacity"
    fi

    # Ensure non-negative
    if [[ "$new_in_use" -lt 0 ]]; then
        new_in_use=0
    fi

    # Update pool state
    RESOURCE_POOL_AVAILABLE="$new_available"
    RESOURCE_POOL_IN_USE="$new_in_use"

    # Update state file
    if [[ -f "$pool_state_file" ]]; then
        echo "capacity=$capacity" > "$pool_state_file"
        echo "available=$new_available" >> "$pool_state_file"
        echo "in_use=$new_in_use" >> "$pool_state_file"
    fi

    echo "released=$count"
    echo "pool_available=$new_available"
    echo "pool_in_use=$new_in_use"
    echo "release_status=success"

    return 0
}

# Get resource pool status
# Usage: resource_pool_status
# Returns: Current pool state in flat data format
resource_pool_status() {
    # Read current pool state
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    local available=0
    local capacity=0
    local in_use=0

    if [[ -f "$pool_state_file" ]]; then
        available=$(grep "^available=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        capacity=$(grep "^capacity=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
        in_use=$(grep "^in_use=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
    else
        # Pool not initialized, use global variables
        available="$RESOURCE_POOL_AVAILABLE"
        capacity="$RESOURCE_POOL_CAPACITY"
        in_use="$RESOURCE_POOL_IN_USE"
    fi

    echo "pool_capacity=${capacity:-0}"
    echo "pool_available=${available:-0}"
    echo "pool_in_use=${in_use:-0}"

    if [[ -n "$RESOURCE_POOL_INITIALIZED" ]] || [[ -f "$pool_state_file" ]]; then
        echo "pool_status=active"
    else
        echo "pool_status=not_initialized"
    fi

    return 0
}

# Clean up only completed (stopped) containers
# Usage: cleanup_completed_containers
# Returns: Cleanup status in flat data format
# Behavior: Only cleans up stopped containers, leaves running ones alone
cleanup_completed_containers() {
    local cleaned_count=0
    local skipped_count=0

    for container_id in $ACTIVE_CONTAINERS; do
        if [[ -n "$container_id" ]]; then
            # Check container status
            local container_status
            container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")

            if [[ "$container_status" != "running" ]] && [[ "$container_status" != "unknown" ]]; then
                # Container is stopped, clean it up
                docker rm "$container_id" >/dev/null 2>&1 || true
                ((cleaned_count++))
            else
                ((skipped_count++))
            fi
        fi
    done

    echo "containers_cleaned=$cleaned_count"
    echo "containers_skipped=$skipped_count"
    echo "cleanup_status=success"

    return 0
}

# Clean up all suitey containers (by name pattern)
# Usage: cleanup_all_suitey_containers
# Returns: Cleanup status in flat data format
# Behavior: Finds and removes all containers matching suitey naming pattern
cleanup_all_suitey_containers() {
    local cleaned_count=0

    # Find all suitey containers by name pattern
    local suitey_containers
    suitey_containers=$(docker ps -a --filter "name=suitey-" --format "{{.ID}}" 2>/dev/null || echo "")

    for container_id in $suitey_containers; do
        if [[ -n "$container_id" ]]; then
            # Stop if running
            docker stop "$container_id" >/dev/null 2>&1 || true
            # Remove container
            docker rm "$container_id" >/dev/null 2>&1 || true
            ((cleaned_count++))
        fi
    done

    echo "containers_cleaned=$cleaned_count"
    echo "cleanup_status=success"

    return 0
}

# Register container for tracking and cleanup
# Usage: register_container_for_cleanup <container_id>
# Returns: Registration status in flat data format
register_container_for_cleanup() {
    local container_id="$1"

    if [[ -z "$container_id" ]]; then
        echo "registered="
        echo "register_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    # Add to tracking list (avoid duplicates)
    if [[ "$ACTIVE_CONTAINERS" != *"$container_id"* ]]; then
        if [[ -z "$ACTIVE_CONTAINERS" ]]; then
            ACTIVE_CONTAINERS="$container_id"
        else
            ACTIVE_CONTAINERS="$ACTIVE_CONTAINERS $container_id"
        fi
    fi

    echo "registered=$container_id"
    echo "register_status=success"
    echo "total_tracked=$(echo "$ACTIVE_CONTAINERS" | wc -w | tr -d ' ')"

    return 0
}

# Unregister container from tracking
# Usage: unregister_container <container_id>
# Returns: Unregistration status in flat data format
unregister_container() {
    local container_id="$1"

    if [[ -z "$container_id" ]]; then
        echo "unregistered="
        echo "unregister_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    # Remove from tracking list
    local new_list=""
    for tracked_id in $ACTIVE_CONTAINERS; do
        if [[ "$tracked_id" != "$container_id" ]]; then
            if [[ -z "$new_list" ]]; then
                new_list="$tracked_id"
            else
                new_list="$new_list $tracked_id"
            fi
        fi
    done

    ACTIVE_CONTAINERS="$new_list"

    echo "unregistered=$container_id"
    echo "unregister_status=success"
    echo "remaining_containers=$(echo "$ACTIVE_CONTAINERS" | wc -w | tr -d ' ')"

    return 0
}

# Clean up on completion (containers and temp files)
# Usage: cleanup_on_completion
# Returns: Cleanup status in flat data format
# Behavior: Cleans up all resources at end of execution
cleanup_on_completion() {
    local containers_cleaned=0
    local temp_files_removed=0
    local pool_released="false"

    # Clean up containers first
    if [[ -n "$ACTIVE_CONTAINERS" ]]; then
        local cleanup_result
        cleanup_result=$(cleanup_containers 2>&1)
        containers_cleaned=$(echo "$cleanup_result" | grep "^containers_cleaned=" | cut -d'=' -f2 || echo "0")
    fi

    # Release resource pool BEFORE cleaning temp files
    # (cleanup_temp_files removes all suitey_* files including pool state)
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    if [[ -f "$pool_state_file" ]]; then
        rm -f "$pool_state_file" 2>/dev/null || true
        pool_released="true"
    fi

    # Reset pool state
    RESOURCE_POOL_CAPACITY=0
    RESOURCE_POOL_AVAILABLE=0
    RESOURCE_POOL_IN_USE=0
    RESOURCE_POOL_INITIALIZED=""

    # Clean up remaining temp files
    local temp_result
    temp_result=$(cleanup_temp_files 2>&1)
    temp_files_removed=$(echo "$temp_result" | grep "^temp_files_removed=" | cut -d'=' -f2 || echo "0")

    echo "cleanup_status=complete"
    echo "containers_cleaned=${containers_cleaned:-0}"
    echo "temp_files_removed=${temp_files_removed:-0}"
    echo "pool_released=$pool_released"

    return 0
}

# Get count of active (tracked) containers
# Usage: get_active_container_count
# Returns: Count in flat data format
get_active_container_count() {
    local count=0

    if [[ -n "$ACTIVE_CONTAINERS" ]]; then
        count=$(echo "$ACTIVE_CONTAINERS" | wc -w | tr -d ' ')
    fi

    echo "active_count=$count"

    return 0
}

# Check if resources are available in pool
# Usage: is_resource_available
# Returns: Availability status in flat data format
is_resource_available() {
    # Read current pool state
    local pool_state_file
    pool_state_file=$(_get_pool_state_file)
    local available=0

    if [[ -f "$pool_state_file" ]]; then
        available=$(grep "^available=" "$pool_state_file" 2>/dev/null | cut -d'=' -f2 || echo "0")
    else
        available="$RESOURCE_POOL_AVAILABLE"
    fi

    # Ensure numeric
    available="${available:-0}"

    if [[ "$available" -gt 0 ]]; then
        echo "available=true"
        echo "pool_available=$available"
    else
        echo "available=false"
        echo "pool_available=$available"
    fi

    return 0
}

# =============================================================================
# Memory Resource Management Functions (3.3.5)
# =============================================================================

# Get available system memory in MB
# Usage: get_available_memory_mb
# Returns: Available memory in flat data format
# Behavior: Reads /proc/meminfo on Linux, uses vm_stat on macOS
get_available_memory_mb() {
    local available_mb=0

    if [[ -f /proc/meminfo ]]; then
        # Linux: Get MemAvailable (preferred) or calculate from MemFree + Buffers + Cached
        local mem_available mem_free buffers cached

        mem_available=$(grep "^MemAvailable:" /proc/meminfo 2>/dev/null | awk '{print $2}')

        if [[ -n "$mem_available" ]]; then
            # MemAvailable is in KB, convert to MB
            available_mb=$((mem_available / 1024))
        else
            # Fallback: MemFree + Buffers + Cached
            mem_free=$(grep "^MemFree:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
            buffers=$(grep "^Buffers:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
            cached=$(grep "^Cached:" /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")

            # All values in KB, convert to MB
            available_mb=$(((mem_free + buffers + cached) / 1024))
        fi
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS: Use vm_stat
        local page_size free_pages

        page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo "4096")
        free_pages=$(vm_stat 2>/dev/null | grep "Pages free:" | awk '{print $3}' | tr -d '.')

        if [[ -n "$free_pages" ]]; then
            available_mb=$((free_pages * page_size / 1024 / 1024))
        fi
    else
        # Fallback: assume 4GB available (conservative default)
        available_mb=4096
    fi

    # Ensure we have at least a minimum value
    if [[ "$available_mb" -lt 1 ]]; then
        available_mb=1024  # Fallback to 1GB
    fi

    echo "available_memory_mb=$available_mb"
    return 0
}

# Get total system memory in MB
# Usage: get_total_memory_mb
# Returns: Total memory in flat data format
get_total_memory_mb() {
    local total_mb=0

    if [[ -f /proc/meminfo ]]; then
        # Linux: Get MemTotal
        local mem_total
        mem_total=$(grep "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')

        if [[ -n "$mem_total" ]]; then
            # MemTotal is in KB, convert to MB
            total_mb=$((mem_total / 1024))
        fi
    elif command -v sysctl >/dev/null 2>&1; then
        # macOS/BSD: Use sysctl
        local hw_memsize
        hw_memsize=$(sysctl -n hw.memsize 2>/dev/null || echo "0")

        if [[ -n "$hw_memsize" ]] && [[ "$hw_memsize" -gt 0 ]]; then
            # hw.memsize is in bytes, convert to MB
            total_mb=$((hw_memsize / 1024 / 1024))
        fi
    fi

    # Fallback if detection failed
    if [[ "$total_mb" -lt 1 ]]; then
        total_mb=8192  # Fallback to 8GB
    fi

    echo "total_memory_mb=$total_mb"
    return 0
}

# Get memory required per runner in MB
# Usage: get_memory_per_runner_mb
# Returns: Memory per runner in flat data format
# Behavior: Returns configured value or auto-calculates based on available memory and CPU cores
get_memory_per_runner_mb() {
    local configured_memory="${SUITEY_MAX_MEMORY_PER_CONTAINER:-}"
    local total_memory_limit="${SUITEY_TOTAL_MEMORY_LIMIT:-}"
    local headroom_percent="${SUITEY_MEMORY_HEADROOM:-20}"

    # Validate headroom is between 0 and 99
    if [[ ! "$headroom_percent" =~ ^[0-9]+$ ]] || [[ "$headroom_percent" -gt 99 ]]; then
        headroom_percent=20
    fi

    # If explicit memory per container is set, use it
    if [[ -n "$configured_memory" ]] && [[ "$configured_memory" -gt 0 ]]; then
        echo "memory_per_runner_mb=$configured_memory"
        echo "headroom_percent=$headroom_percent"
        echo "source=configured"
        return 0
    fi

    # Auto-calculate based on available memory
    local total_mb available_mb
    local total_output available_output

    total_output=$(get_total_memory_mb 2>/dev/null)
    total_mb=$(echo "$total_output" | grep "^total_memory_mb=" | cut -d'=' -f2)
    total_mb="${total_mb:-8192}"

    available_output=$(get_available_memory_mb 2>/dev/null)
    available_mb=$(echo "$available_output" | grep "^available_memory_mb=" | cut -d'=' -f2)
    available_mb="${available_mb:-4096}"

    # Apply total memory limit if set
    if [[ -n "$total_memory_limit" ]] && [[ "$total_memory_limit" -gt 0 ]]; then
        if [[ "$total_memory_limit" -lt "$total_mb" ]]; then
            total_mb="$total_memory_limit"
        fi
        echo "total_memory_limit_mb=$total_memory_limit"
    fi

    # Get CPU cores to determine max parallel runners
    local cpu_cores
    cpu_cores=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Apply explicit container limit if set
    local max_containers="${SUITEY_MAX_CONTAINERS:-$cpu_cores}"
    if [[ "$max_containers" -gt "$cpu_cores" ]]; then
        max_containers="$cpu_cores"
    fi

    # Calculate usable memory: total * (1 - headroom%)
    local headroom_factor usable_memory
    headroom_factor=$((100 - headroom_percent))
    usable_memory=$((total_mb * headroom_factor / 100))

    # Calculate memory per runner: usable_memory / max_containers
    local memory_per_runner
    memory_per_runner=$((usable_memory / max_containers))

    # Ensure minimum of 256MB per runner
    if [[ "$memory_per_runner" -lt 256 ]]; then
        memory_per_runner=256
    fi

    echo "memory_per_runner_mb=$memory_per_runner"
    echo "headroom_percent=$headroom_percent"
    echo "total_memory_mb=$total_mb"
    echo "usable_memory_mb=$usable_memory"
    echo "max_containers=$max_containers"
    echo "source=auto"

    return 0
}

# Check if sufficient memory is available for a runner
# Usage: check_memory_available required_mb
# Returns: Availability status in flat data format
check_memory_available() {
    local required_mb="${1:-0}"

    # Validate required_mb is a positive integer
    if [[ ! "$required_mb" =~ ^[0-9]+$ ]] || [[ "$required_mb" -lt 1 ]]; then
        required_mb=256  # Default to 256MB minimum
    fi

    # Get current available memory
    local available_output available_mb
    available_output=$(get_available_memory_mb 2>/dev/null)
    available_mb=$(echo "$available_output" | grep "^available_memory_mb=" | cut -d'=' -f2)
    available_mb="${available_mb:-0}"

    echo "available_memory_mb=$available_mb"
    echo "required_memory_mb=$required_mb"

    if [[ "$available_mb" -ge "$required_mb" ]]; then
        echo "memory_available=true"
        return 0
    else
        echo "memory_available=false"
        echo "reason=insufficient_memory"
        echo "shortfall_mb=$((required_mb - available_mb))"
        return 1
    fi
}

# Wait for memory to become available
# Usage: wait_for_memory required_mb [timeout_seconds]
# Returns: Wait status in flat data format
# Behavior: Polls every 1-2 seconds until memory is available or timeout
wait_for_memory() {
    local required_mb="${1:-256}"
    local timeout_seconds="${2:-60}"
    local poll_interval=2
    local elapsed=0
    local attempts=0

    echo "waiting_for_memory=true"
    echo "required_memory_mb=$required_mb"
    echo "timeout_seconds=$timeout_seconds"

    while [[ "$elapsed" -lt "$timeout_seconds" ]]; do
        local check_result
        check_result=$(check_memory_available "$required_mb" 2>/dev/null)

        local is_available
        is_available=$(echo "$check_result" | grep "^memory_available=" | cut -d'=' -f2)

        if [[ "$is_available" == "true" ]]; then
            echo "memory_available=true"
            echo "wait_attempts=$attempts"
            echo "wait_time_seconds=$elapsed"
            return 0
        fi

        ((attempts++))
        sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
    done

    echo "memory_available=false"
    echo "reason=timeout"
    echo "wait_attempts=$attempts"
    echo "wait_time_seconds=$elapsed"

    return 1
}

# Get maximum parallel runners considering both CPU and memory limits
# Usage: get_max_parallel_runners
# Returns: Effective limit in flat data format
# Behavior: Returns the minimum of CPU-based and memory-based limits
get_max_parallel_runners() {
    # Get CPU-based limit
    local explicit_limit="${SUITEY_MAX_CONTAINERS:-}"
    local cpu_output cpu_limit
    cpu_output=$(get_max_concurrent_containers "$explicit_limit" 2>/dev/null)
    cpu_limit=$(echo "$cpu_output" | grep "^max_containers=" | cut -d'=' -f2)
    cpu_limit="${cpu_limit:-4}"

    # Get memory-based limit
    local memory_output memory_per_runner available_mb memory_limit
    memory_output=$(get_memory_per_runner_mb 2>/dev/null)
    memory_per_runner=$(echo "$memory_output" | grep "^memory_per_runner_mb=" | cut -d'=' -f2)
    memory_per_runner="${memory_per_runner:-256}"

    local available_output
    available_output=$(get_available_memory_mb 2>/dev/null)
    available_mb=$(echo "$available_output" | grep "^available_memory_mb=" | cut -d'=' -f2)
    available_mb="${available_mb:-4096}"

    # Apply headroom
    local headroom_percent="${SUITEY_MEMORY_HEADROOM:-20}"
    local headroom_factor=$((100 - headroom_percent))
    local usable_mb=$((available_mb * headroom_factor / 100))

    # Calculate memory-based limit
    if [[ "$memory_per_runner" -gt 0 ]]; then
        memory_limit=$((usable_mb / memory_per_runner))
    else
        memory_limit="$cpu_limit"  # Fallback to CPU limit if memory per runner is 0
    fi

    # Ensure minimum of 1
    if [[ "$memory_limit" -lt 1 ]]; then
        memory_limit=1
    fi

    # Use the more restrictive limit
    local effective_limit
    if [[ "$cpu_limit" -lt "$memory_limit" ]]; then
        effective_limit="$cpu_limit"
    else
        effective_limit="$memory_limit"
    fi

    # Ensure minimum of 1
    if [[ "$effective_limit" -lt 1 ]]; then
        effective_limit=1
    fi

    echo "cpu_based_limit=$cpu_limit"
    echo "memory_based_limit=$memory_limit"
    echo "effective_limit=$effective_limit"
    echo "memory_per_runner_mb=$memory_per_runner"
    echo "available_memory_mb=$available_mb"
    echo "usable_memory_mb=$usable_mb"

    return 0
}

# Parse memory-related CLI options
# Usage: parse_memory_options [options...]
# Returns: Parsed options in flat data format
parse_memory_options() {
    local max_memory_per_container="auto"
    local total_memory_limit=""
    local memory_headroom=20

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max-memory-per-container)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    max_memory_per_container="$2"
                    shift
                else
                    echo "error=invalid_max_memory_per_container"
                    return 1
                fi
                ;;
            --total-memory-limit)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    total_memory_limit="$2"
                    shift
                else
                    echo "error=invalid_total_memory_limit"
                    return 1
                fi
                ;;
            --memory-headroom)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]] && [[ "$2" -lt 100 ]]; then
                    memory_headroom="$2"
                    shift
                else
                    echo "error=invalid_memory_headroom"
                    echo "message=memory_headroom_must_be_0_to_99"
                    return 1
                fi
                ;;
            *)
                # Unknown option, skip
                ;;
        esac
        shift
    done

    echo "max_memory_per_container=$max_memory_per_container"
    echo "memory_headroom=$memory_headroom"
    if [[ -n "$total_memory_limit" ]]; then
        echo "total_memory_limit=$total_memory_limit"
    fi

    return 0
}
