#!/usr/bin/env bash

# Build System Detector
# Determines if and how projects need to be built before testing
# Aggregates build requirements from all detected platforms
#
# Filesystem Isolation: This module only reads from project directories.
# Build execution happens in isolated Docker containers with read-only
# project access. No modifications are made to the project filesystem.

# Source required dependencies
source "src/data_access.sh" 2>/dev/null || true

# Detect build requirements for detected platforms
# Usage: detect_build_requirements <platform_data>
# Returns: Build requirements in flat data format
# Behavior: Calls detect_build_requirements on each detected platform's module
detect_build_requirements() {
    local platform_data="$1"

    # Initialize result data
    local result=""
    local requires_build=false
    local total_build_commands_count=0
    local total_build_dependencies_count=0
    local total_build_artifacts_count=0

    # Parse platform data to get platforms count
    local platforms_count
    platforms_count=$(data_get "$platform_data" "platforms_count")

    if [[ -z "$platforms_count" ]] || [[ "$platforms_count" -eq 0 ]]; then
        # No platforms detected, no build required
        result="requires_build=false"$'\n'
        result="${result}build_commands_count=0"$'\n'
        result="${result}build_dependencies_count=0"$'\n'
        result="${result}build_artifacts_count=0"
        echo "$result"
        return 0
    fi

    # Process each detected platform
    local i=0
    while [[ $i -lt "$platforms_count" ]]; do
        local language
        local framework
        local module_type

        language=$(data_get "$platform_data" "platforms_${i}_language")
        framework=$(data_get "$platform_data" "platforms_${i}_framework")
        module_type=$(data_get "$platform_data" "platforms_${i}_module_type")

        # Determine module file path based on platform type
        local module_file=""
        case "$module_type" in
            "language")
                module_file="mod/languages/${language}/mod.sh"
                ;;
            "framework")
                module_file="mod/frameworks/${framework}/mod.sh"
                ;;
            "tool")
                module_file="mod/tools/${framework}/mod.sh"
                ;;
        esac

        # If module file exists, load it in a subshell to avoid function conflicts
        if [[ -n "$module_file" ]] && [[ -f "$module_file" ]]; then
            # Get the project root from the platform data
            local project_root
            project_root=$(data_get "$platform_data" "project_root" || echo ".")

            # Execute the module's detect_build_requirements in a subshell
            local module_result
            module_result=$(bash -c "
                source '$module_file' 2>/dev/null
                detect_build_requirements '$project_root' '$platform_data' 2>/dev/null
            " || echo "requires_build=false")

            # Check if this platform requires building
            local platform_requires_build
            platform_requires_build=$(echo "$module_result" | grep "^requires_build=" | cut -d'=' -f2 || echo "false")

            if [[ "$platform_requires_build" == "true" ]]; then
                requires_build=true

                # Aggregate build commands
                local build_commands_count
                build_commands_count=$(echo "$module_result" | grep "^build_commands_count=" | cut -d'=' -f2 || echo "0")

                local j=0
                while [[ $j -lt "$build_commands_count" ]]; do
                    local build_command
                    build_command=$(echo "$module_result" | grep "^build_commands_${j}=" | cut -d'=' -f2 || echo "")

                    if [[ -n "$build_command" ]]; then
                        result=$(data_set "$result" "build_commands_${total_build_commands_count}" "$build_command")
                        ((total_build_commands_count++))
                    fi
                    ((j++))
                done

                # Aggregate build dependencies
                local build_dependencies_count
                build_dependencies_count=$(echo "$module_result" | grep "^build_dependencies_count=" | cut -d'=' -f2 || echo "0")

                local j=0
                while [[ $j -lt "$build_dependencies_count" ]]; do
                    local build_dependency
                    build_dependency=$(echo "$module_result" | grep "^build_dependencies_${j}=" | cut -d'=' -f2 || echo "")

                    if [[ -n "$build_dependency" ]]; then
                        result=$(data_set "$result" "build_dependencies_${total_build_dependencies_count}" "$build_dependency")
                        ((total_build_dependencies_count++))
                    fi
                    ((j++))
                done

                # Aggregate build artifacts
                local build_artifacts_count
                build_artifacts_count=$(echo "$module_result" | grep "^build_artifacts_count=" | cut -d'=' -f2 || echo "0")

                local j=0
                while [[ $j -lt "$build_artifacts_count" ]]; do
                    local build_artifact
                    build_artifact=$(echo "$module_result" | grep "^build_artifacts_${j}=" | cut -d'=' -f2 || echo "")

                    if [[ -n "$build_artifact" ]]; then
                        result=$(data_set "$result" "build_artifacts_${total_build_artifacts_count}" "$build_artifact")
                        ((total_build_artifacts_count++))
                    fi
                    ((j++))
                done
            fi
        fi

        ((i++))
    done

    # Set final results
    result=$(data_set "$result" "requires_build" "$requires_build")
    result=$(data_set "$result" "build_commands_count" "$total_build_commands_count")
    result=$(data_set "$result" "build_dependencies_count" "$total_build_dependencies_count")
    result=$(data_set "$result" "build_artifacts_count" "$total_build_artifacts_count")

    echo "$result"
    return 0
}

# Get detailed build steps for detected platforms
# Usage: get_build_steps <platform_data> <build_requirements>
# Returns: Detailed build steps in flat data format
# Behavior: Returns containerized build specifications. Build execution
#           happens in isolated Docker containers with read-only project
#           access. Project directories are never modified.
get_build_steps() {
    local platform_data="$1"
    local build_requirements="$2"

    # Initialize result data
    local result=""
    local total_build_steps_count=0

    # Parse platform data to get platforms count
    local platforms_count
    platforms_count=$(data_get "$platform_data" "platforms_count")

    if [[ -z "$platforms_count" ]] || [[ "$platforms_count" -eq 0 ]]; then
        # No platforms detected, no build steps
        result="build_steps_count=0"
        echo "$result"
        return 0
    fi

    # Check if building is required overall
    local requires_build
    requires_build=$(echo "$build_requirements" | grep "^requires_build=" | cut -d'=' -f2 || echo "false")

    if [[ "$requires_build" != "true" ]]; then
        result="build_steps_count=0"
        echo "$result"
        return 0
    fi

    # Process each detected platform
    local i=0
    while [[ $i -lt "$platforms_count" ]]; do
        local language
        local framework
        local module_type

        language=$(data_get "$platform_data" "platforms_${i}_language")
        framework=$(data_get "$platform_data" "platforms_${i}_framework")
        module_type=$(data_get "$platform_data" "platforms_${i}_module_type")

        # Determine module file path based on platform type
        local module_file=""
        case "$module_type" in
            "language")
                module_file="mod/languages/${language}/mod.sh"
                ;;
            "framework")
                module_file="mod/frameworks/${framework}/mod.sh"
                ;;
            "tool")
                module_file="mod/tools/${framework}/mod.sh"
                ;;
        esac

        # If module file exists, load it in a subshell to avoid function conflicts
        if [[ -n "$module_file" ]] && [[ -f "$module_file" ]]; then
            # Get the project root from the platform data
            local project_root
            project_root=$(data_get "$platform_data" "project_root" || echo ".")

            # Execute the module's get_build_steps in a subshell
            local module_result
            module_result=$(bash -c "
                source '$module_file' 2>/dev/null
                get_build_steps '$project_root' '$build_requirements' 2>/dev/null
            " || echo "build_steps_count=0")

            # Check if this platform has build steps
            local build_steps_count
            build_steps_count=$(echo "$module_result" | grep "^build_steps_count=" | cut -d'=' -f2 || echo "0")

            local j=0
            while [[ $j -lt "$build_steps_count" ]]; do
                # Copy all build step data with updated index
                local step_prefix="build_steps_${j}"
                local new_step_prefix="build_steps_${total_build_steps_count}"

                # Get all lines for this build step
                local step_lines
                step_lines=$(echo "$module_result" | grep "^${step_prefix}_")

                # Add each line with updated index
                while IFS= read -r line; do
                    if [[ -n "$line" ]]; then
                        local new_line="${line/${step_prefix}_/${new_step_prefix}_}"
                        result=$(data_set "$result" "${new_line%%=*}" "${new_line#*=}")
                    fi
                done <<< "$step_lines"

                ((total_build_steps_count++))
                ((j++))
            done
        fi

        ((i++))
    done

    # Set final results
    result=$(data_set "$result" "build_steps_count" "$total_build_steps_count")

    echo "$result"
    return 0
}

# Analyze dependencies between build steps
# Usage: analyze_build_dependencies <build_steps>
# Returns: Dependency analysis in flat data format
# Behavior: Analyzes build step dependencies and determines execution order
analyze_build_dependencies() {
    local build_steps="$1"

    # Initialize result data
    local result=""
    local execution_order=""
    local parallel_groups_count=0
    local dependency_graph=""

    # Parse build steps count
    local build_steps_count
    build_steps_count=$(echo "$build_steps" | grep "^build_steps_count=" | cut -d'=' -f2 || echo "0")

    if [[ -z "$build_steps_count" ]] || [[ "$build_steps_count" -eq 0 ]]; then
        # No build steps, no dependencies to analyze
        result="execution_order_count=0"$'\n'
        result="${result}parallel_groups_count=0"$'\n'
        result="${result}dependency_graph_count=0"
        echo "$result"
        return 0
    fi

    # For now, implement a simple dependency analysis
    # In a real implementation, this would analyze actual dependencies between build steps
    # For this phase, we'll assume all build steps can run in parallel (no dependencies)

    # Create execution order (simple sequential for now)
    local execution_order_list=""
    local i=0
    while [[ $i -lt "$build_steps_count" ]]; do
        if [[ -n "$execution_order_list" ]]; then
            execution_order_list="${execution_order_list},"
        fi
        execution_order_list="${execution_order_list}${i}"
        ((i++))
    done

    result="execution_order_count=${build_steps_count}"$'\n'
    result="${result}execution_order_steps=${execution_order_list}"$'\n'

    # For now, assume all builds can run in parallel (no dependencies)
    # In a real implementation, this would analyze dependencies and create groups
    result="${result}parallel_groups_count=1"$'\n'
    result="${result}parallel_groups_0_step_count=${build_steps_count}"$'\n'
    result="${result}parallel_groups_0_steps=${execution_order_list}"$'\n'

    # Simple dependency graph (no dependencies for now)
    result="${result}dependency_graph_count=0"

    echo "$result"
    return 0
}
