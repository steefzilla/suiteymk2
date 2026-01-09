#!/usr/bin/env bash

# Suitey Platform Detector
# Identifies which programming languages/frameworks are present in a project
# Uses Suitey Modules Registry to coordinate language-specific detection
# No external dependencies

# Source data access functions if available (for parsing flat data)
if [[ -f "src/data_access.sh" ]]; then
    source "src/data_access.sh" 2>/dev/null || true
fi

# Check container environment readiness
# Usage: check_container_environment
# Returns: Container environment status as flat data
# Behavior: Verifies Docker daemon accessibility, basic container operations, and network connectivity
check_container_environment() {
    local results=""

    # Check Docker command availability
    local docker_command_available="false"
    if command -v docker >/dev/null 2>&1; then
        docker_command_available="true"
    fi
    results="${results}docker_command_available=${docker_command_available}"$'\n'

    # Check Docker daemon accessibility (only if command is available)
    local docker_daemon_available="false"
    if [[ "$docker_command_available" == "true" ]]; then
        # Check if docker daemon is accessible
        if docker info >/dev/null 2>&1; then
            docker_daemon_available="true"
        fi
    fi
    results="${results}docker_daemon_available=${docker_daemon_available}"$'\n'

    # Check basic container operations (only if daemon is available)
    local container_operations="false"
    if [[ "$docker_daemon_available" == "true" ]]; then
        # Try to run a simple container operation
        if docker run --rm alpine:latest echo "test" >/dev/null 2>&1; then
            container_operations="true"
        fi
    fi
    results="${results}container_operations=${container_operations}"$'\n'

    # Check network connectivity for image pulls (only if daemon is available)
    local network_access="false"
    if [[ "$docker_daemon_available" == "true" ]]; then
        # Try to pull a small image to test network access
        if docker pull alpine:latest >/dev/null 2>&1; then
            network_access="true"
            # Clean up the pulled image
            docker rmi alpine:latest >/dev/null 2>&1 || true
        fi
    fi
    results="${results}network_access=${network_access}"$'\n'

    # Provide backward compatibility aliases
    results="${results}docker_available=${docker_daemon_available}"$'\n'

    echo "$results"
}

# Detect platforms in a project
# Usage: detect_platforms <project_root>
# Returns: Detection results as flat data
# Behavior: Uses Modules Registry to get all modules, calls each module's detect() method, aggregates results
detect_platforms() {
    local project_root="$1"

    # Validate input
    if [[ -z "$project_root" ]]; then
        echo "platforms_count=0"
        return 0
    fi

    # Get all registered modules
    local modules
    modules=$(get_all_modules 2>/dev/null || echo "")

    if [[ -z "$modules" ]]; then
        echo "platforms_count=0"
        return 0
    fi

    # Track detected platforms
    local platforms_count=0
    local platform_index=0
    local results=""

    # Check container environment readiness
    local container_env_status
    container_env_status=$(check_container_environment 2>/dev/null || echo "")
    if [[ -n "$container_env_status" ]]; then
        results="${results}${container_env_status}"
    fi

    # Process each module
    while IFS= read -r module_id || [[ -n "$module_id" ]]; do
        # Determine module file path based on module_id
        # Module IDs follow pattern: {language}-module or {framework}-module
        # Module files are at: mod/languages/{language}/mod.sh or mod/frameworks/{framework}/mod.sh
        local module_file=""

        # Try language modules first
        if [[ "$module_id" == *"-module" ]]; then
            local language="${module_id%-module}"
            module_file="mod/languages/${language}/mod.sh"
        fi

        # If not a language module, try framework modules
        if [[ ! -f "$module_file" ]] && [[ "$module_id" == *"-module" ]]; then
            local framework="${module_id%-module}"
            module_file="mod/frameworks/${framework}/mod.sh"
        fi

        # If not found, skip
        if [[ ! -f "$module_file" ]]; then
            continue
        fi

        # Clean up any existing module functions to avoid conflicts
        for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
            unset -f "$method" 2>/dev/null || true
        done

        # Source the module
        source "$module_file" 2>/dev/null || continue

        # Call module's detect() method
        local detection_result
        detection_result=$(detect "$project_root" 2>/dev/null || echo "")

        if [[ -z "$detection_result" ]]; then
            continue
        fi

        # Check if platform was detected
        local detected
        if declare -f data_get >/dev/null 2>&1; then
            detected=$(data_get "$detection_result" "detected" || echo "false")
        else
            detected=$(echo "$detection_result" | grep "^detected=" | cut -d'=' -f2 || echo "false")
        fi

        if [[ "$detected" == "true" ]]; then
            # Platform detected - extract language and framework from detection result
            local language
            local framework
            local confidence

            if declare -f data_get >/dev/null 2>&1; then
                language=$(data_get "$detection_result" "language" || echo "")
                framework=$(data_get "$detection_result" "frameworks_0" || echo "")
                confidence=$(data_get "$detection_result" "confidence" || echo "low")
            else
                language=$(echo "$detection_result" | grep "^language=" | cut -d'=' -f2 || echo "")
                framework=$(echo "$detection_result" | grep "^frameworks_0=" | cut -d'=' -f2 || echo "")
                confidence=$(echo "$detection_result" | grep "^confidence=" | cut -d'=' -f2 || echo "low")
            fi

            # Add platform to results
            if [[ -n "$results" ]]; then
                results="${results}"$'\n'"platforms_${platform_index}_language=${language}"
            else
                results="platforms_${platform_index}_language=${language}"
            fi

            if [[ -n "$framework" ]]; then
                results="${results}"$'\n'"platforms_${platform_index}_framework=${framework}"
            fi

            results="${results}"$'\n'"platforms_${platform_index}_confidence=${confidence}"
            results="${results}"$'\n'"platforms_${platform_index}_module_id=${module_id}"

            # Add detection indicators
            local indicators_count
            if declare -f data_array_count >/dev/null 2>&1; then
                indicators_count=$(data_array_count "$detection_result" "indicators" || echo "0")
            else
                indicators_count=$(echo "$detection_result" | grep "^indicators_count=" | cut -d'=' -f2 || echo "0")
            fi
            results="${results}"$'\n'"platforms_${platform_index}_indicators_count=${indicators_count}"

            # Add individual indicators
            local i=0
            while [[ $i -lt "$indicators_count" ]]; do
                local indicator
                if declare -f data_get_array >/dev/null 2>&1; then
                    indicator=$(data_get_array "$detection_result" "indicators" "$i" || echo "")
                else
                    indicator=$(echo "$detection_result" | grep "^indicators_${i}=" | cut -d'=' -f2 || echo "")
                fi
                if [[ -n "$indicator" ]]; then
                    results="${results}"$'\n'"platforms_${platform_index}_indicators_${i}=${indicator}"
                fi
                i=$((i + 1))
            done


            platforms_count=$((platforms_count + 1))
            platform_index=$((platform_index + 1))
        fi
    done <<< "$modules"

    # Output results
    echo "platforms_count=${platforms_count}"
    if [[ -n "$results" ]]; then
        echo "$results"
    fi

    return 0
}
