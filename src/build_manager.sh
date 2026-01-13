#!/usr/bin/env bash

# Build Manager
# Manages Docker container lifecycle for build execution
# Handles container launch, tracking, and cleanup

# Source required dependencies
source "src/data_access.sh" 2>/dev/null || true

# Launch a build container with specified configuration
# Usage: launch_build_container <container_config>
# Returns: Container ID in flat data format
# Behavior: Launches Docker container with read-only project mount and read-write /tmp mount
launch_build_container() {
    local container_config="$1"

    # Parse container configuration
    local docker_image=$(echo "$container_config" | grep "^docker_image=" | cut -d'=' -f2 || echo "")
    local project_root=$(echo "$container_config" | grep "^project_root=" | cut -d'=' -f2 || echo ".")
    local working_directory=$(echo "$container_config" | grep "^working_directory=" | cut -d'=' -f2 || echo "/workspace")
    local cpu_cores=$(echo "$container_config" | grep "^cpu_cores=" | cut -d'=' -f2 || echo "0")
    local container_name=$(echo "$container_config" | grep "^container_name=" | cut -d'=' -f2 || echo "")

    # Validate required parameters
    if [[ -z "$docker_image" ]]; then
        echo "Error: docker_image is required" >&2
        echo "container_id="
        echo "container_status=error"
        echo "error_message=docker_image is required"
        return 1
    fi

    if [[ ! -d "$project_root" ]]; then
        echo "Error: Project root directory does not exist: $project_root" >&2
        echo "container_id="
        echo "container_status=error"
        echo "error_message=Project root directory does not exist"
        return 1
    fi

    # Create temporary directory for build artifacts
    local artifact_dir
    artifact_dir=$(mktemp -d -t suitey-build-XXXXXX 2>/dev/null || echo "/tmp/suitey-build-$$")

    # Build Docker run command
    local docker_cmd="docker run -d"
    
    # Mount project directory read-only
    docker_cmd="$docker_cmd --mount type=bind,source=$(realpath "$project_root"),target=/workspace,readonly"
    
    # Mount /tmp directory read-write for artifacts
    docker_cmd="$docker_cmd --mount type=bind,source=$artifact_dir,target=/tmp/build-artifacts"
    
    # Set working directory
    docker_cmd="$docker_cmd -w $working_directory"
    
    # Set CPU cores if specified (0 means use all available)
    if [[ "$cpu_cores" != "0" ]] && [[ -n "$cpu_cores" ]]; then
        docker_cmd="$docker_cmd --cpus=$cpu_cores"
    fi
    
    # Set container name if specified
    if [[ -n "$container_name" ]]; then
        docker_cmd="$docker_cmd --name $container_name"
    else
        # Generate unique container name
        local unique_name="suitey-build-$$-$(date +%s)"
        docker_cmd="$docker_cmd --name $unique_name"
        container_name="$unique_name"
    fi
    
    # Add image
    docker_cmd="$docker_cmd $docker_image"
    
    # Command to keep container running (will be replaced by actual build command)
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
    echo "artifact_dir=$artifact_dir"
    echo "project_root=$project_root"
    echo "docker_image=$docker_image"
    echo "working_directory=$working_directory"
    
    return 0
}

# Track container status
# Usage: track_container <container_id>
# Returns: Container status in flat data format
track_container() {
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
        # Try with short ID match
        found_id=$(docker ps -a --format "{{.ID}}" | grep "^${container_id}" | head -1)
    fi

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

# Clean up container
# Usage: cleanup_container <container_id>
# Returns: Cleanup status in flat data format
cleanup_container() {
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

# Clean up multiple containers
# Usage: cleanup_containers <container_ids>
# Returns: Cleanup results in flat data format
cleanup_containers() {
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
        cleanup_result=$(cleanup_container "$container_id" 2>&1)
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

# Execute build command in a running container
# Usage: execute_build_command <container_id> <build_command>
# Returns: Build execution results in flat data format
# Behavior: Executes command, captures output, tracks duration, detects failures
execute_build_command() {
    local container_id="$1"
    local build_command="$2"

    # Validate required parameters
    if [[ -z "$container_id" ]]; then
        echo "Error: container_id is required" >&2
        echo "build_status=error"
        echo "error_message=container_id is required"
        return 1
    fi

    if [[ -z "$build_command" ]]; then
        echo "Error: build_command is required" >&2
        echo "build_status=error"
        echo "error_message=build_command is required"
        return 1
    fi

    # Find the full container ID first
    local found_id
    found_id=$(docker ps -a --format "{{.ID}}" | grep "^${container_id}" | head -1)

    if [[ -z "$found_id" ]]; then
        echo "Error: Container not found: $container_id" >&2
        echo "build_status=error"
        echo "container_status=error"
        echo "error_message=Container not found: $container_id"
        return 1
    fi

    # Verify container exists and is running
    local container_status
    container_status=$(track_container "$container_id" 2>/dev/null | grep "^container_status=" | cut -d'=' -f2 || echo "")
    
    if [[ "$container_status" != "running" ]]; then
        echo "Error: Container is not running: $container_id" >&2
        echo "build_status=error"
        echo "container_status=error"
        echo "error_message=Container is not running (status: $container_status)"
        return 1
    fi

    # Record start time for duration tracking
    local start_time
    start_time=$(date +%s.%N 2>/dev/null || date +%s)

    # Execute build command and capture output
    # Use docker exec to run the command in the container
    # Capture both stdout and stderr separately
    local stdout_file
    stdout_file=$(mktemp -t suitey-build-stdout-XXXXXX 2>/dev/null || echo "/tmp/suitey-build-stdout-$$")
    local stderr_file
    stderr_file=$(mktemp -t suitey-build-stderr-XXXXXX 2>/dev/null || echo "/tmp/suitey-build-stderr-$$")

    # Execute command, capturing stdout and stderr separately
    # Use sh -c to properly handle the command
    # Set PATH to include common locations for build tools
    docker exec "$found_id" sh -c "export PATH=\$PATH:/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && $build_command" > "$stdout_file" 2> "$stderr_file"
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

    # Determine build status
    local build_status
    if [[ $exit_code -eq 0 ]]; then
        build_status="success"
    else
        build_status="failed"
    fi

    # Return results in flat data format
    echo "container_id=$container_id"
    echo "build_status=$build_status"
    echo "exit_code=$exit_code"
    echo "duration=$duration"
    echo "stdout=$stdout_content"
    echo "stderr=$stderr_content"

    return 0
}

