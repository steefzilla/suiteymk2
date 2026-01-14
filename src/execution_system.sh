#!/usr/bin/env bash

# Execution System
# Manages test container lifecycle and test execution
# Handles container launch, test execution, and result collection

# Source required dependencies
source "src/data_access.sh" 2>/dev/null || true
source "src/mod_registry.sh" 2>/dev/null || true

# Launch a test container with pre-built test image
# Usage: launch_test_container <container_config>
# Returns: Container ID in flat data format
# Behavior: Launches Docker container with pre-built test image (no volume mounts needed)
launch_test_container() {
    local container_config="$1"

    # Parse container configuration
    local test_image=$(echo "$container_config" | grep "^test_image=" | cut -d'=' -f2 || echo "")
    local working_directory=$(echo "$container_config" | grep "^working_directory=" | cut -d'=' -f2 || echo "/app")
    local cpu_cores=$(echo "$container_config" | grep "^cpu_cores=" | cut -d'=' -f2 || echo "0")
    local container_name=$(echo "$container_config" | grep "^container_name=" | cut -d'=' -f2 || echo "")

    # Validate required parameters
    if [[ -z "$test_image" ]]; then
        echo "Error: test_image is required" >&2
        echo "container_id="
        echo "container_status=error"
        echo "error_message=test_image is required"
        return 1
    fi

    # Verify test image exists
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${test_image}" 2>/dev/null && \
       ! docker images --format "{{.ID}}" | grep -q "^${test_image}" 2>/dev/null; then
        echo "Error: Test image not found: $test_image" >&2
        echo "container_id="
        echo "container_status=error"
        echo "error_message=Test image not found: $test_image"
        return 1
    fi

    # Build Docker run command
    local docker_cmd="docker run -d"
    
    # Set working directory
    docker_cmd="$docker_cmd -w $working_directory"
    
    # Set CPU cores if specified (0 means use all available)
    if [[ "$cpu_cores" != "0" ]] && [[ -n "$cpu_cores" ]]; then
        # Use allocate_cpu_cores if available (from build_manager.sh)
        if command -v allocate_cpu_cores >/dev/null 2>&1; then
            local allocation_result
            allocation_result=$(allocate_cpu_cores "$cpu_cores" 2>/dev/null || echo "")
            if [[ -n "$allocation_result" ]]; then
                local allocated_cores
                allocated_cores=$(echo "$allocation_result" | grep "^allocated_cores=" | cut -d'=' -f2 || echo "$cpu_cores")
                if [[ -n "$allocated_cores" ]] && [[ "$allocated_cores" != "0" ]]; then
                    docker_cmd="$docker_cmd --cpus=$allocated_cores"
                fi
            fi
        else
            docker_cmd="$docker_cmd --cpus=$cpu_cores"
        fi
    fi
    
    # Set container name if specified
    if [[ -n "$container_name" ]]; then
        docker_cmd="$docker_cmd --name $container_name"
    else
        # Generate unique container name
        local unique_name="suitey-test-$$-$(date +%s)"
        docker_cmd="$docker_cmd --name $unique_name"
        container_name="$unique_name"
    fi
    
    # Add test image
    docker_cmd="$docker_cmd $test_image"
    
    # Command to keep container running (will be replaced by actual test command)
    docker_cmd="$docker_cmd sleep infinity"

    # Launch container
    local container_output
    container_output=$(eval "$docker_cmd" 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]] || [[ -z "$container_output" ]]; then
        echo "Error: Failed to launch container: $container_output" >&2
        echo "container_id="
        echo "container_status=error"
        echo "error_message=Failed to launch container: $container_output"
        return 1
    fi

    # Extract container ID (Docker returns full ID, we'll use short ID for consistency)
    local container_id
    container_id=$(echo "$container_output" | head -1 | tr -d '[:space:]')
    
    # Get short ID for easier handling
    local short_id
    short_id=$(echo "$container_id" | cut -c1-12)

    # Return container information
    echo "container_id=$short_id"
    echo "container_name=$container_name"
    echo "container_status=running"
    echo "test_image=$test_image"
    echo "working_directory=$working_directory"
    
    return 0
}

# Execute test command in a running test container
# Usage: execute_test_command <container_id> <test_command>
# Returns: Test execution results in flat data format
# Behavior: Executes test command, captures output, tracks duration, detects test status
execute_test_command() {
    local container_id="$1"
    local test_command="$2"

    # Validate required parameters
    if [[ -z "$container_id" ]]; then
        echo "Error: container_id is required" >&2
        echo "test_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    if [[ -z "$test_command" ]]; then
        echo "Error: test_command is required" >&2
        echo "test_status=error"
        echo "error_message=test_command is required"
        return 1
    fi

    # Find the full container ID
    local found_id
    found_id=$(docker ps -a --format "{{.ID}}" | grep "^${container_id}" | head -1)

    if [[ -z "$found_id" ]]; then
        echo "Error: Container not found: $container_id" >&2
        echo "test_status=error"
        echo "error_message=Container not found: $container_id"
        return 1
    fi

    # Verify container exists and is running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$found_id" 2>/dev/null || echo "unknown")
    
    if [[ "$container_status" != "running" ]]; then
        echo "Error: Container is not running: $container_id" >&2
        echo "test_status=error"
        echo "container_status=$container_status"
        echo "error_message=Container is not running (status: $container_status)"
        return 1
    fi

    # Record start time for duration tracking
    local start_time
    start_time=$(date +%s.%N 2>/dev/null || date +%s)

    # Execute test command and capture output
    # Use docker exec to run the command in the container
    # Capture both stdout and stderr separately
    local stdout_file
    stdout_file=$(mktemp -t suitey-test-stdout-XXXXXX 2>/dev/null || echo "/tmp/suitey-test-stdout-$$")
    local stderr_file
    stderr_file=$(mktemp -t suitey-test-stderr-XXXXXX 2>/dev/null || echo "/tmp/suitey-test-stderr-$$")

    # Execute command, capturing stdout and stderr separately
    # Use sh -c to properly handle the command
    # Set PATH to include common locations for test runners
    docker exec "$found_id" sh -c "export PATH=\$PATH:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $test_command" > "$stdout_file" 2> "$stderr_file"
    local exit_code=$?

    # Record end time
    local end_time
    end_time=$(date +%s.%N 2>/dev/null || date +%s)

    # Calculate duration (in seconds with decimal precision)
    local duration
    if command -v bc >/dev/null 2>&1; then
        duration=$(echo "scale=3; $end_time - $start_time" | bc 2>/dev/null || echo "0")
        # Ensure duration is not negative (handle clock adjustments)
        if [[ "$(echo "$duration < 0" | bc 2>/dev/null || echo "0")" = "1" ]]; then
            duration="0.001"
        fi
    else
        # Fallback for systems without bc - use integer arithmetic
        local start_int end_int
        start_int=$(echo "$start_time" | cut -d'.' -f1)
        end_int=$(echo "$end_time" | cut -d'.' -f1)
        if [[ -z "$start_int" ]] || [[ -z "$end_int" ]]; then
            duration="0.0"
        else
            duration=$((end_int - start_int))
            # Ensure non-negative
            if [[ $duration -lt 0 ]]; then
                duration=0
            fi
            duration="${duration}.0"
        fi
    fi

    # Read captured output
    local stdout_content
    stdout_content=$(cat "$stdout_file" 2>/dev/null || echo "")
    local stderr_content
    stderr_content=$(cat "$stderr_file" 2>/dev/null || echo "")

    # Clean up temporary files
    rm -f "$stdout_file" "$stderr_file" 2>/dev/null || true

    # Determine test status
    local test_status
    if [[ $exit_code -eq 0 ]]; then
        test_status="passed"
    else
        test_status="failed"
    fi

    # Return results in flat data format
    echo "container_id=$container_id"
    echo "test_status=$test_status"
    echo "exit_code=$exit_code"
    echo "duration=$duration"
    echo "stdout=$stdout_content"
    echo "stderr=$stderr_content"

    return 0
}

# Track test container status
# Usage: track_test_container <container_id>
# Returns: Container status in flat data format
track_test_container() {
    local container_id="$1"

    if [[ -z "$container_id" ]]; then
        echo "container_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    # Try to find container by short ID or full ID
    local found_id
    found_id=$(docker ps -a --format "{{.ID}}" | grep "^${container_id}" | head -1)

    if [[ -z "$found_id" ]]; then
        echo "container_status=not_found"
        echo "error_message=Container not found: $container_id"
        return 1
    fi

    # Use the found ID for inspection
    local inspect_id="$found_id"

    # Get container status
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$inspect_id" 2>/dev/null || echo "unknown")

    echo "container_id=$container_id"
    echo "container_status=$status"
    
    # Get additional information if container is running
    if [[ "$status" == "running" ]]; then
        local exit_code
        exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$inspect_id" 2>/dev/null || echo "0")
        echo "exit_code=$exit_code"
    fi

    return 0
}

# Clean up test container
# Usage: cleanup_test_container <container_id>
# Returns: Cleanup status in flat data format
cleanup_test_container() {
    local container_id="$1"

    if [[ -z "$container_id" ]]; then
        echo "cleanup_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    # Try to find container by short ID or full ID
    local found_id
    found_id=$(docker ps -a --format "{{.ID}}" | grep "^${container_id}" | head -1)

    if [[ -z "$found_id" ]]; then
        # Container not found, but that's okay (might already be cleaned up)
        echo "cleanup_status=success"
        echo "container_id=$container_id"
        echo "message=Container not found (may already be cleaned up)"
        return 0
    fi

    # Use the found ID for operations
    local cleanup_id="$found_id"

    # Stop container if running
    docker stop "$cleanup_id" >/dev/null 2>&1 || true

    # Remove container
    local remove_result
    remove_result=$(docker rm "$cleanup_id" 2>&1)
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        echo "cleanup_status=success"
        echo "container_id=$container_id"
    else
        echo "cleanup_status=error"
        echo "container_id=$container_id"
        echo "error_message=Failed to remove container: $remove_result"
        return 1
    fi

    return 0
}

# Clean up multiple test containers
# Usage: cleanup_test_containers <container_ids>
# Returns: Cleanup results in flat data format
cleanup_test_containers() {
    local container_ids="$1"
    local result=""
    local cleaned_count=0
    local failed_count=0

    # Parse container IDs (space or newline separated)
    while IFS= read -r container_id || [[ -n "$container_id" ]]; do
        container_id=$(echo "$container_id" | tr -d '[:space:]')
        
        if [[ -z "$container_id" ]]; then
            continue
        fi

        # Clean up container
        local cleanup_result
        cleanup_result=$(cleanup_test_container "$container_id" 2>&1)
        local cleanup_status
        cleanup_status=$(echo "$cleanup_result" | grep "^cleanup_status=" | cut -d'=' -f2 || echo "error")

        if [[ "$cleanup_status" == "success" ]]; then
            ((cleaned_count++))
        else
            ((failed_count++))
        fi

        result="${result}${cleanup_result}"$'\n'
    done <<< "$container_ids"

    # Add summary
    result="${result}cleanup_total_count=$((cleaned_count + failed_count))"$'\n'
    result="${result}cleanup_success_count=$cleaned_count"$'\n'
    result="${result}cleanup_failed_count=$failed_count"$'\n'

    echo "$result"
    return 0
}

# Collect test results and write to /tmp with unique filenames
# Usage: collect_test_results <suite_id> <test_result_data>
# Returns: Result file paths in flat data format
# Behavior: Writes structured results to /tmp following Test Guidelines for Parallel Execution
#           Uses unique filenames ($$ and $RANDOM) and atomic writes (temp file, then mv)
collect_test_results() {
    local suite_id="$1"
    local test_result_data="$2"

    # Validate required parameters
    if [[ -z "$suite_id" ]]; then
        echo "Error: suite_id is required" >&2
        echo "result_file="
        echo "output_file="
        echo "error_message=suite_id is required"
        return 1
    fi

    # Generate unique filenames following Test Guidelines for Parallel Execution
    # Pattern: /tmp/suitey_test_result_<suite_id>_$$_$RANDOM
    local result_filename="/tmp/suitey_test_result_${suite_id}_$$_$RANDOM"
    local output_filename="/tmp/suitey_test_output_${suite_id}_$$_$RANDOM"

    # Extract stdout and stderr from test result data
    local stdout_content
    stdout_content=$(echo "$test_result_data" | grep "^stdout=" | cut -d'=' -f2- || echo "")
    local stderr_content
    stderr_content=$(echo "$test_result_data" | grep "^stderr=" | cut -d'=' -f2- || echo "")

    # Create temporary files for atomic writes
    local result_temp_file
    result_temp_file=$(mktemp -t suitey-result-temp-XXXXXX 2>/dev/null || echo "/tmp/suitey-result-temp-$$-$RANDOM")
    local output_temp_file
    output_temp_file=$(mktemp -t suitey-output-temp-XXXXXX 2>/dev/null || echo "/tmp/suitey-output-temp-$$-$RANDOM")

    # Write structured result data to temp file
    echo "$test_result_data" > "$result_temp_file"

    # Write output data (stdout and stderr) to temp file
    {
        if [[ -n "$stdout_content" ]]; then
            echo "=== STDOUT ==="
            echo "$stdout_content"
        fi
        if [[ -n "$stderr_content" ]]; then
            echo "=== STDERR ==="
            echo "$stderr_content"
        fi
    } > "$output_temp_file"

    # Atomic write: move temp files to final location
    if ! mv "$result_temp_file" "$result_filename" 2>/dev/null; then
        rm -f "$result_temp_file" "$output_temp_file" 2>/dev/null || true
        echo "Error: Failed to write result file" >&2
        echo "result_file="
        echo "output_file="
        echo "error_message=Failed to write result file"
        return 1
    fi

    if ! mv "$output_temp_file" "$output_filename" 2>/dev/null; then
        rm -f "$result_filename" "$output_temp_file" 2>/dev/null || true
        echo "Error: Failed to write output file" >&2
        echo "result_file=$result_filename"
        echo "output_file="
        echo "error_message=Failed to write output file"
        return 1
    fi

    # Return file paths in flat data format
    echo "result_file=$result_filename"
    echo "output_file=$output_filename"
    echo "suite_id=$suite_id"
    echo "status=success"

    return 0
}

# Parse test results using module's parse_test_results() method
# Usage: parse_test_results_with_module <module_identifier> <test_output> <exit_code>
# Returns: Parsed test results in flat data format
# Behavior: Sources the module, calls its parse_test_results() method, and returns parsed results
parse_test_results_with_module() {
    local module_identifier="$1"
    local test_output="$2"
    local exit_code="$3"

    # Validate required parameters
    if [[ -z "$module_identifier" ]]; then
        echo "Error: module_identifier is required" >&2
        echo "status=error"
        echo "error_message=module_identifier is required"
        return 1
    fi

    if [[ -z "$test_output" ]] && [[ -z "$exit_code" ]]; then
        echo "Error: test_output or exit_code is required" >&2
        echo "status=error"
        echo "error_message=test_output or exit_code is required"
        return 1
    fi

    # Get module file path from identifier
    # Module identifiers follow pattern: {name}-module
    # Module files are at: mod/languages/{name}/mod.sh, mod/frameworks/{name}/mod.sh, or mod/tools/{name}/mod.sh
    local module_file=""
    local name="${module_identifier%-module}"

    # Try framework modules first (most common for test parsing)
    if [[ -f "mod/frameworks/${name}/mod.sh" ]]; then
        module_file="mod/frameworks/${name}/mod.sh"
    # Try language modules
    elif [[ -f "mod/languages/${name}/mod.sh" ]]; then
        module_file="mod/languages/${name}/mod.sh"
    # Try tool modules
    elif [[ -f "mod/tools/${name}/mod.sh" ]]; then
        module_file="mod/tools/${name}/mod.sh"
    fi

    # If module file not found, try to get from registry
    if [[ -z "$module_file" ]] || [[ ! -f "$module_file" ]]; then
        # Check if module is registered
        if declare -f get_module >/dev/null 2>&1; then
            local module_name
            module_name=$(get_module "$module_identifier" 2>/dev/null || echo "")
            if [[ -n "$module_name" ]]; then
                # Extract path from module name (format: mod/.../mod.sh)
                module_file="$module_name"
            fi
        fi
    fi

    # If still not found, return error
    if [[ -z "$module_file" ]] || [[ ! -f "$module_file" ]]; then
        echo "Error: Module not found: $module_identifier" >&2
        echo "status=error"
        echo "error_message=Module not found: $module_identifier"
        return 1
    fi

    # Clean up any existing module functions to avoid conflicts
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Source the module
    if ! source "$module_file" 2>/dev/null; then
        echo "Error: Failed to load module: $module_file" >&2
        echo "status=error"
        echo "error_message=Failed to load module: $module_file"
        return 1
    fi

    # Verify parse_test_results function exists
    if ! declare -f parse_test_results >/dev/null 2>&1; then
        echo "Error: Module does not implement parse_test_results() method" >&2
        echo "status=error"
        echo "error_message=Module does not implement parse_test_results() method"
        return 1
    fi

    # Call module's parse_test_results() method
    # Use subshell to avoid polluting current environment
    local parsed_result
    parsed_result=$(parse_test_results "$test_output" "$exit_code" 2>&1)
    local parse_exit_code=$?

    # Clean up module functions after use
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Return parsed results
    if [[ $parse_exit_code -eq 0 ]]; then
        echo "$parsed_result"
        return 0
    else
        # Even if parsing failed, return what we got (module may have returned partial results)
        echo "$parsed_result"
        echo "parse_status=error" >> /dev/stderr || true
        return 1
    fi
}

# Execute test suite using module's execute_test_suite() method
# Usage: execute_test_suite_with_module <module_identifier> <test_suite> <test_image> <execution_config>
# Returns: Execution configuration in flat data format
# Behavior: Sources the module, calls its execute_test_suite() method, and returns execution configuration
execute_test_suite_with_module() {
    local module_identifier="$1"
    local test_suite="$2"
    local test_image="$3"
    local execution_config="$4"

    # Validate required parameters
    if [[ -z "$module_identifier" ]]; then
        echo "Error: module_identifier is required" >&2
        echo "status=error"
        echo "error_message=module_identifier is required"
        return 1
    fi

    if [[ -z "$test_suite" ]]; then
        echo "Error: test_suite is required" >&2
        echo "status=error"
        echo "error_message=test_suite is required"
        return 1
    fi

    # Get module file path from identifier
    # Module identifiers follow pattern: {name}-module
    # Module files are at: mod/languages/{name}/mod.sh, mod/frameworks/{name}/mod.sh, or mod/tools/{name}/mod.sh
    local module_file=""
    local name="${module_identifier%-module}"

    # Try framework modules first (most common for test execution)
    if [[ -f "mod/frameworks/${name}/mod.sh" ]]; then
        module_file="mod/frameworks/${name}/mod.sh"
    # Try language modules
    elif [[ -f "mod/languages/${name}/mod.sh" ]]; then
        module_file="mod/languages/${name}/mod.sh"
    # Try tool modules
    elif [[ -f "mod/tools/${name}/mod.sh" ]]; then
        module_file="mod/tools/${name}/mod.sh"
    fi

    # If module file not found, try to get from registry
    if [[ -z "$module_file" ]] || [[ ! -f "$module_file" ]]; then
        # Check if module is registered
        if declare -f get_module >/dev/null 2>&1; then
            local module_name
            module_name=$(get_module "$module_identifier" 2>/dev/null || echo "")
            if [[ -n "$module_name" ]]; then
                # Extract path from module name (format: mod/.../mod.sh)
                module_file="$module_name"
            fi
        fi
    fi

    # If still not found, return error
    if [[ -z "$module_file" ]] || [[ ! -f "$module_file" ]]; then
        echo "Error: Module not found: $module_identifier" >&2
        echo "status=error"
        echo "error_message=Module not found: $module_identifier"
        return 1
    fi

    # Clean up any existing module functions to avoid conflicts
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Source the module
    if ! source "$module_file" 2>/dev/null; then
        echo "Error: Failed to load module: $module_file" >&2
        echo "status=error"
        echo "error_message=Failed to load module: $module_file"
        return 1
    fi

    # Verify execute_test_suite function exists
    if ! declare -f execute_test_suite >/dev/null 2>&1; then
        echo "Error: Module does not implement execute_test_suite() method" >&2
        echo "status=error"
        echo "error_message=Module does not implement execute_test_suite() method"
        return 1
    fi

    # Call module's execute_test_suite() method
    # Use subshell to avoid polluting current environment
    local execution_result
    execution_result=$(execute_test_suite "$test_suite" "$test_image" "$execution_config" 2>&1)
    local execution_exit_code=$?

    # Clean up module functions after use
    for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
        unset -f "$method" 2>/dev/null || true
    done

    # Return execution results
    if [[ $execution_exit_code -eq 0 ]]; then
        echo "$execution_result"
        return 0
    else
        # Even if execution failed, return what we got (module may have returned partial results)
        echo "$execution_result"
        echo "execution_status=error" >> /dev/stderr || true
        return 1
    fi
}

