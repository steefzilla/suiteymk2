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

    # Get available CPU cores for parallelism limiting
    local max_parallel
    max_parallel=$(get_available_cpu_cores 2>/dev/null || echo "4")

    # Launch suites in batches based on available cores
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
