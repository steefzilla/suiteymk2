#!/usr/bin/env bash

# Test Suite Detector
# This file implements test suite discovery for detected platforms

# Source required dependencies
source "src/data_access.sh" 2>/dev/null || true

# Discover test suites for detected platforms
# Directly loads and calls module discover_test_suites methods based on platform type
# Returns aggregated results in flat data format
discover_test_suites() {
    local platform_data="$1"

    # Initialize result data
    local result="suites_count=0"

    # Parse platform data to get platforms count
    local platforms_count
    platforms_count=$(data_get "$platform_data" "platforms_count")

    if [[ -z "$platforms_count" ]] || [[ "$platforms_count" -eq 0 ]]; then
        echo "$result"
        return 0
    fi

    # Process each detected platform
    local suite_index=0
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
            "project")
                # Project modules would be handled differently
                module_file=""
                ;;
        esac

        # If module file exists, load it and call discover_test_suites
        if [[ -n "$module_file" ]] && [[ -f "$module_file" ]]; then
            # Clean up any existing module functions to avoid conflicts
            for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
                unset -f "$method" 2>/dev/null || true
            done

            # Source the module
            source "$module_file" 2>/dev/null || continue

            # Get the project root from the platform data
            local project_root
            project_root=$(data_get "$platform_data" "project_root" || echo ".")

            # Call the module's discover_test_suites method
            local module_result
            module_result=$(discover_test_suites "$project_root" "$platform_data" 2>/dev/null || echo "suites_count=0")

            # Parse the module result and add to our result
            local module_suites_count
            module_suites_count=$(data_get "$module_result" "suites_count")

            if [[ -n "$module_suites_count" ]] && [[ "$module_suites_count" -gt 0 ]]; then
                # Add each suite from this module to our result
                local j=0
                while [[ $j -lt "$module_suites_count" ]]; do
                    # Copy suite data from module result to our result
                    local suite_prefix="suites_${suite_index}"
                    local module_suite_prefix="suites_${j}"

                    # Get all lines for this suite from module result
                    local suite_lines
                    suite_lines=$(echo "$module_result" | grep "^${module_suite_prefix}_")

                    # Add each line with updated index
                    while IFS= read -r line; do
                        if [[ -n "$line" ]]; then
                            local new_line="${line/${module_suite_prefix}_/${suite_prefix}_}"
                            result=$(data_set "$result" "${new_line%%=*}" "${new_line#*=}")
                        fi
                    done <<< "$suite_lines"

                    ((suite_index++))
                    ((j++))
                done
            fi

            # Clean up module functions after use
            for method in detect check_binaries discover_test_suites detect_build_requirements get_build_steps execute_test_suite parse_test_results get_metadata; do
                unset -f "$method" 2>/dev/null || true
            done
        fi

        ((i++))
    done

    # Update the final suites count
    result=$(data_set "$result" "suites_count" "$suite_index")

    echo "$result"
}

