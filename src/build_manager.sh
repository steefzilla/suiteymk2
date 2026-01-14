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
    # Use allocate_cpu_cores to handle allocation logic
    local allocated_cores
    if [[ "$cpu_cores" != "0" ]] && [[ -n "$cpu_cores" ]]; then
        local allocation_result
        allocation_result=$(allocate_cpu_cores "$cpu_cores" 2>/dev/null || echo "")
        if [[ -n "$allocation_result" ]]; then
            allocated_cores=$(echo "$allocation_result" | grep "^allocated_cores=" | cut -d'=' -f2 || echo "$cpu_cores")
        else
            allocated_cores="$cpu_cores"
        fi
    else
        # Use all available cores
        allocated_cores=$(get_available_cpu_cores)
    fi
    
    # Set CPU cores in Docker command
    if [[ -n "$allocated_cores" ]] && [[ "$allocated_cores" != "0" ]]; then
        docker_cmd="$docker_cmd --cpus=$allocated_cores"
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

# Get available CPU cores on the system
# Usage: get_available_cpu_cores
# Returns: Number of available CPU cores as integer
# Behavior: Detects CPU cores using nproc or fallback methods, handles single-core systems
get_available_cpu_cores() {
    local cores=1  # Default to 1 core

    # Try nproc first (most reliable on Linux)
    if command -v nproc >/dev/null 2>&1; then
        cores=$(nproc 2>/dev/null || echo "1")
    # Try sysctl on macOS/BSD
    elif command -v sysctl >/dev/null 2>&1; then
        cores=$(sysctl -n hw.ncpu 2>/dev/null || echo "1")
    # Try /proc/cpuinfo on Linux
    elif [[ -f /proc/cpuinfo ]]; then
        cores=$(grep -c "^processor" /proc/cpuinfo 2>/dev/null || echo "1")
    fi

    # Ensure we have at least 1 core
    if [[ -z "$cores" ]] || [[ "$cores" -lt 1 ]]; then
        cores=1
    fi

    # Return as integer
    echo "$cores"
    return 0
}

# Get parallel build flags for a build system
# Usage: get_parallel_build_flags <build_system>
# Returns: Parallel build flags string (e.g., "-j4" for make, "--jobs 4" for cargo)
# Behavior: Generates appropriate parallel flags based on build system and available cores
get_parallel_build_flags() {
    local build_system="$1"
    local cores
    cores=$(get_available_cpu_cores)

    # Ensure we have at least 1 core
    if [[ -z "$cores" ]] || [[ "$cores" -lt 1 ]]; then
        cores=1
    fi

    case "$build_system" in
        "cargo"|"rust")
            # Cargo uses --jobs flag
            echo "--jobs $cores"
            ;;
        "make"|"gmake")
            # Make uses -j flag
            echo "-j$cores"
            ;;
        "cmake")
            # CMake uses -j flag with build command
            echo "-j$cores"
            ;;
        "ninja")
            # Ninja uses -j flag
            echo "-j$cores"
            ;;
        "maven"|"mvn")
            # Maven uses -T flag for parallel builds
            echo "-T $cores"
            ;;
        "gradle")
            # Gradle uses --parallel and --max-workers
            echo "--parallel --max-workers=$cores"
            ;;
        *)
            # Unknown build system - return empty or default
            # Some build systems don't need explicit parallel flags
            echo ""
            ;;
    esac

    return 0
}

# Allocate CPU cores for build container
# Usage: allocate_cpu_cores [requested_cores]
# Returns: Number of cores to allocate in flat data format
# Behavior: Allocates cores based on request and availability, handles single-core systems
allocate_cpu_cores() {
    local requested_cores="$1"
    local available_cores
    available_cores=$(get_available_cpu_cores)

    # If no cores requested, use all available
    if [[ -z "$requested_cores" ]] || [[ "$requested_cores" == "0" ]]; then
        echo "allocated_cores=$available_cores"
        echo "available_cores=$available_cores"
        echo "allocation_strategy=all_available"
        return 0
    fi

    # Validate requested cores is a positive integer
    if ! [[ "$requested_cores" =~ ^[0-9]+$ ]]; then
        echo "allocated_cores=1"
        echo "available_cores=$available_cores"
        echo "allocation_strategy=default"
        echo "error_message=Invalid core count requested, using default"
        return 0
    fi

    # Allocate requested cores, but not more than available
    local allocated_cores
    if [[ "$requested_cores" -gt "$available_cores" ]]; then
        allocated_cores=$available_cores
        echo "allocated_cores=$allocated_cores"
        echo "available_cores=$available_cores"
        echo "requested_cores=$requested_cores"
        echo "allocation_strategy=limited_by_availability"
        echo "warning_message=Requested $requested_cores cores but only $available_cores available"
    else
        allocated_cores=$requested_cores
        echo "allocated_cores=$allocated_cores"
        echo "available_cores=$available_cores"
        echo "requested_cores=$requested_cores"
        echo "allocation_strategy=requested"
    fi

    # Ensure at least 1 core is allocated
    if [[ "$allocated_cores" -lt 1 ]]; then
        allocated_cores=1
        echo "allocated_cores=$allocated_cores"
        echo "allocation_strategy=minimum"
    fi

    return 0
}

# Generate Dockerfile for test image
# Usage: generate_test_image_dockerfile <image_config>
# Returns: Dockerfile content as text
# Behavior: Generates Dockerfile with base image, artifacts, source code, and test suites
generate_test_image_dockerfile() {
    local image_config="$1"

    # Parse configuration
    local base_image=$(echo "$image_config" | grep "^base_image=" | cut -d'=' -f2 || echo "")
    local artifact_dir=$(echo "$image_config" | grep "^artifact_dir=" | cut -d'=' -f2 || echo "")
    local project_root=$(echo "$image_config" | grep "^project_root=" | cut -d'=' -f2 || echo ".")
    local framework=$(echo "$image_config" | grep "^framework=" | cut -d'=' -f2 || echo "")

    # Validate required parameters
    if [[ -z "$base_image" ]]; then
        echo "Error: base_image is required" >&2
        return 1
    fi

    # Start Dockerfile
    echo "FROM $base_image"
    echo ""
    echo "# Set working directory"
    echo "WORKDIR /app"
    echo ""

    # Copy build artifacts if artifact directory is specified
    if [[ -n "$artifact_dir" ]] && [[ -d "$artifact_dir" ]]; then
        echo "# Copy build artifacts"
        echo "COPY artifacts/ /app/"
        echo ""
    fi

    # Copy source code if project root is specified
    if [[ -n "$project_root" ]] && [[ -d "$project_root" ]]; then
        echo "# Copy source code"
        # Copy source files (exclude common build/test directories)
        echo "COPY source/ /app/"
        echo ""
    fi

    # Copy test suites
    if [[ -n "$project_root" ]] && [[ -d "$project_root" ]]; then
        echo "# Copy test suites"
        echo "COPY tests/ /app/tests/"
        echo ""
    fi

    # Set environment variables based on framework
    case "$framework" in
        "rust"|"cargo")
            echo "# Rust/Cargo environment"
            echo "ENV CARGO_TARGET_DIR=/app/target"
            echo "ENV RUST_BACKTRACE=1"
            ;;
        "python")
            echo "# Python environment"
            echo "ENV PYTHONPATH=/app"
            ;;
        "node"|"javascript")
            echo "# Node.js environment"
            echo "ENV NODE_PATH=/app"
            ;;
    esac

    echo ""
    echo "# Default command (can be overridden)"
    echo "CMD [\"/bin/sh\"]"

    return 0
}

# Build Docker image from generated Dockerfile
# Usage: build_test_image <image_config>
# Returns: Image build results in flat data format
# Behavior: Builds Docker image with artifacts, source code, and test suites
build_test_image() {
    local image_config="$1"

    # Parse configuration
    local base_image=$(echo "$image_config" | grep "^base_image=" | cut -d'=' -f2 || echo "")
    local artifact_dir=$(echo "$image_config" | grep "^artifact_dir=" | cut -d'=' -f2 || echo "")
    local project_root=$(echo "$image_config" | grep "^project_root=" | cut -d'=' -f2 || echo ".")
    local framework=$(echo "$image_config" | grep "^framework=" | cut -d'=' -f2 || echo "")
    local image_tag=$(echo "$image_config" | grep "^image_tag=" | cut -d'=' -f2 || echo "")

    # Validate required parameters
    if [[ -z "$base_image" ]]; then
        echo "Error: base_image is required" >&2
        echo "build_status=error"
        echo "error_message=base_image is required"
        return 1
    fi

    # Generate image tag if not provided
    if [[ -z "$image_tag" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "$(date +%s)")
        image_tag="suitey-test-${framework}-${timestamp}-$$"
    fi

    # Create temporary build context directory
    local build_context
    build_context=$(mktemp -d -t suitey-build-context-XXXXXX 2>/dev/null || echo "/tmp/suitey-build-context-$$")
    mkdir -p "$build_context"

    # Generate Dockerfile
    local dockerfile_content
    dockerfile_content=$(generate_test_image_dockerfile "$image_config" 2>/dev/null)
    if [[ $? -ne 0 ]] || [[ -z "$dockerfile_content" ]]; then
        echo "Error: Failed to generate Dockerfile" >&2
        echo "build_status=error"
        echo "error_message=Failed to generate Dockerfile"
        rm -rf "$build_context"
        return 1
    fi

    # Write Dockerfile to build context
    echo "$dockerfile_content" > "$build_context/Dockerfile"

    # Copy artifacts to build context if specified
    if [[ -n "$artifact_dir" ]] && [[ -d "$artifact_dir" ]]; then
        mkdir -p "$build_context/artifacts"
        cp -r "$artifact_dir"/* "$build_context/artifacts/" 2>/dev/null || true
    fi

    # Copy source code to build context if specified
    if [[ -n "$project_root" ]] && [[ -d "$project_root" ]]; then
        mkdir -p "$build_context/source"
        # Copy source files, excluding common build/test directories
        find "$project_root" -type f \( -name "*.rs" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.sh" -o -name "*.toml" -o -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) ! -path "*/target/*" ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/tests/*" 2>/dev/null | while read -r file; do
            local rel_path="${file#$project_root/}"
            local dest_dir="$build_context/source/$(dirname "$rel_path")"
            mkdir -p "$dest_dir"
            cp "$file" "$build_context/source/$rel_path" 2>/dev/null || true
        done
    fi

    # Copy test suites to build context if specified
    if [[ -n "$project_root" ]] && [[ -d "$project_root/tests" ]]; then
        mkdir -p "$build_context/tests"
        cp -r "$project_root/tests"/* "$build_context/tests/" 2>/dev/null || true
    fi

    # Build Docker image
    local build_output
    build_output=$(cd "$build_context" && docker build -t "$image_tag" . 2>&1)
    local build_exit_code=$?

    # Clean up build context
    rm -rf "$build_context" 2>/dev/null || true

    if [[ $build_exit_code -ne 0 ]]; then
        echo "Error: Failed to build Docker image: $build_output" >&2
        echo "build_status=error"
        echo "image_tag=$image_tag"
        echo "error_message=Failed to build Docker image"
        return 1
    fi

    # Get image ID
    local image_id
    image_id=$(docker images --format "{{.ID}}" "$image_tag" 2>/dev/null | head -1)

    # Return results
    echo "build_status=success"
    echo "image_tag=$image_tag"
    echo "image_id=$image_id"
    echo "base_image=$base_image"
    echo "framework=$framework"

    return 0
}

# Verify test image contains required components
# Usage: verify_test_image <verification_config>
# Returns: Verification results in flat data format
# Behavior: Verifies image contains artifacts, source code, and test suites
verify_test_image() {
    local verification_config="$1"

    # Parse configuration
    local image_tag=$(echo "$verification_config" | grep "^image_tag=" | cut -d'=' -f2 || echo "")
    local artifact_paths=$(echo "$verification_config" | grep "^artifact_paths=" | cut -d'=' -f2- || echo "")
    local source_paths=$(echo "$verification_config" | grep "^source_paths=" | cut -d'=' -f2- || echo "")
    local test_suite_paths=$(echo "$verification_config" | grep "^test_suite_paths=" | cut -d'=' -f2- || echo "")

    # Validate required parameters
    if [[ -z "$image_tag" ]]; then
        echo "Error: image_tag is required" >&2
        echo "verification_status=error"
        echo "error_message=image_tag is required"
        return 1
    fi

    # Check if image exists
    if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image_tag}" 2>/dev/null; then
        # Try without tag (use latest)
        if ! docker images --format "{{.ID}}" | grep -q "^${image_tag}" 2>/dev/null; then
            echo "Error: Image not found: $image_tag" >&2
            echo "verification_status=error"
            echo "error_message=Image not found: $image_tag"
            return 1
        fi
    fi

    local artifacts_verified="false"
    local source_verified="false"
    local test_suites_verified="false"
    local all_verified="true"

    # Verify artifacts if specified
    if [[ -n "$artifact_paths" ]]; then
        local artifact_found="true"
        while IFS= read -r path || [[ -n "$path" ]]; do
            if [[ -n "$path" ]]; then
                path=$(echo "$path" | tr -d '[:space:]')
                if ! docker run --rm "$image_tag" test -f "$path" 2>/dev/null && ! docker run --rm "$image_tag" test -d "$path" 2>/dev/null; then
                    artifact_found="false"
                    break
                fi
            fi
        done < <(echo "$artifact_paths" | tr ':' '\n')
        if [[ "$artifact_found" == "true" ]]; then
            artifacts_verified="true"
        else
            all_verified="false"
        fi
    fi

    # Verify source code if specified
    if [[ -n "$source_paths" ]]; then
        local source_found="true"
        while IFS= read -r path || [[ -n "$path" ]]; do
            if [[ -n "$path" ]]; then
                path=$(echo "$path" | tr -d '[:space:]')
                if ! docker run --rm "$image_tag" test -f "$path" 2>/dev/null && ! docker run --rm "$image_tag" test -d "$path" 2>/dev/null; then
                    source_found="false"
                    break
                fi
            fi
        done < <(echo "$source_paths" | tr ':' '\n')
        if [[ "$source_found" == "true" ]]; then
            source_verified="true"
        else
            all_verified="false"
        fi
    fi

    # Verify test suites if specified
    if [[ -n "$test_suite_paths" ]]; then
        local test_suite_found="true"
        while IFS= read -r path || [[ -n "$path" ]]; do
            if [[ -n "$path" ]]; then
                path=$(echo "$path" | tr -d '[:space:]')
                if ! docker run --rm "$image_tag" test -f "$path" 2>/dev/null && ! docker run --rm "$image_tag" test -d "$path" 2>/dev/null; then
                    test_suite_found="false"
                    break
                fi
            fi
        done < <(echo "$test_suite_paths" | tr ':' '\n')
        if [[ "$test_suite_found" == "true" ]]; then
            test_suites_verified="true"
        else
            all_verified="false"
        fi
    fi

    # Return verification results
    if [[ "$all_verified" == "true" ]]; then
        echo "verification_status=success"
    else
        echo "verification_status=partial"
    fi
    echo "artifacts_verified=$artifacts_verified"
    echo "source_verified=$source_verified"
    echo "test_suites_verified=$test_suites_verified"
    echo "image_tag=$image_tag"

    return 0
}

