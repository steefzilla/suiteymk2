#!/usr/bin/env bash

# Suitey Modules Registry
# Centralized registry for Suitey Modules with registration, lookup, and lifecycle management
# No external dependencies

# Registry storage (using associative arrays)
declare -A MODULE_REGISTRY
declare -A MODULE_METADATA

# Required interface methods that all modules must implement
readonly REQUIRED_METHODS=(
    "detect"
    "check_binaries"
    "discover_test_suites"
    "detect_build_requirements"
    "get_build_steps"
    "execute_test_suite"
    "parse_test_results"
    "get_metadata"
)

# Reset the registry (for testing)
reset_registry() {
    # Clear arrays (use -g to ensure we're modifying global arrays)
    unset MODULE_REGISTRY MODULE_METADATA
    declare -gA MODULE_REGISTRY
    declare -gA MODULE_METADATA
}

# Validate that a module implements all required interface methods
# Usage: validate_module_interface
# Exit code: 0 if valid, 1 if invalid
# Note: This should be called after sourcing a module script
validate_module_interface() {
    # Check if all required methods exist as functions
    for method in "${REQUIRED_METHODS[@]}"; do
        # Check if method exists as a function
        if ! declare -f "$method" >/dev/null 2>&1; then
            return 1
        fi
    done

    return 0
}

# Validate module metadata structure
# Usage: validate_module_metadata <metadata_data>
# Exit code: 0 if valid, 1 if invalid
validate_module_metadata() {
    local metadata="$1"

    # Basic validation: check that metadata is not empty
    if [[ -z "$metadata" ]]; then
        return 1
    fi

    # Check for required fields (can be lenient for now)
    # At minimum, should have language field
    if ! echo "$metadata" | grep -q "^language="; then
        return 1
    fi

    return 0
}

# Register a Suitey module
# Usage: register_module <identifier> <module_name>
# Exit code: 0 on success, 1 on error
# Note: Module should be sourced before calling this function
register_module() {
    local identifier="$1"
    local module_name="$2"

    # Validate identifier is not empty
    if [[ -z "$identifier" ]]; then
        echo "Error: Module identifier cannot be empty" >&2
        return 1
    fi

    # Check if module is already registered
    if [[ -n "${MODULE_REGISTRY[$identifier]}" ]]; then
        echo "Error: Module with identifier '$identifier' is already registered" >&2
        return 1
    fi

    # Validate module interface (check if required methods exist as functions)
    # Modules are sourced before registration, so functions should be available
    local interface_valid=true
    for method in "${REQUIRED_METHODS[@]}"; do
        # Check if method exists as a function
        if ! declare -f "$method" >/dev/null 2>&1; then
            echo "Error: Module '$identifier' is missing required method '$method'" >&2
            interface_valid=false
        fi
    done

    if [[ "$interface_valid" == false ]]; then
        return 1
    fi

    # Get module metadata
    local metadata=""
    if declare -f "get_metadata" >/dev/null 2>&1; then
        metadata=$(get_metadata)
    else
        echo "Error: Module '$identifier' does not provide get_metadata() method" >&2
        return 1
    fi

    # Validate metadata
    if ! validate_module_metadata "$metadata"; then
        echo "Error: Module '$identifier' has invalid metadata" >&2
        return 1
    fi

    # Register the module
    MODULE_REGISTRY[$identifier]="$module_name"
    MODULE_METADATA[$identifier]="$metadata"

    return 0
}

# Get a module by identifier
# Usage: get_module <identifier>
# Exit code: 0 on success, 1 if not found
get_module() {
    local identifier="$1"

    if [[ -z "$identifier" ]]; then
        echo "Error: Module identifier cannot be empty" >&2
        return 1
    fi

    if [[ -z "${MODULE_REGISTRY[$identifier]}" ]]; then
        echo "Error: Module '$identifier' not found" >&2
        return 1
    fi

    echo "${MODULE_REGISTRY[$identifier]}"
    return 0
}

# Get module metadata by identifier
# Usage: get_module_metadata <identifier>
# Exit code: 0 on success, 1 if not found
get_module_metadata() {
    local identifier="$1"

    if [[ -z "$identifier" ]]; then
        echo "Error: Module identifier cannot be empty" >&2
        return 1
    fi

    if [[ -z "${MODULE_METADATA[$identifier]}" ]]; then
        echo "Error: Module '$identifier' not found" >&2
        return 1
    fi

    echo "${MODULE_METADATA[$identifier]}"
    return 0
}

# Get all registered module identifiers
# Usage: get_all_modules
# Returns: List of module identifiers, one per line
get_all_modules() {
    # Ensure arrays are initialized
    if [[ -z "${MODULE_REGISTRY[*]}" ]]; then
        return 0
    fi

    local identifier
    for identifier in "${!MODULE_REGISTRY[@]}"; do
        echo "$identifier"
    done
}

# Get modules by capability
# Usage: get_modules_by_capability <capability>
# Returns: List of module identifiers that have the specified capability, one per line
get_modules_by_capability() {
    local capability="$1"

    if [[ -z "$capability" ]]; then
        return 0
    fi

    local identifier
    local modules=""
    for identifier in "${!MODULE_REGISTRY[@]}"; do
        # Get module metadata
        local metadata="${MODULE_METADATA[$identifier]}"
        
        if [[ -z "$metadata" ]]; then
            continue
        fi

        # Check if metadata contains the capability
        # Capabilities are stored as capabilities_0=..., capabilities_1=..., etc.
        # Use grep to check for capability in metadata
        if echo "$metadata" | grep -q "^capabilities_[0-9]*=${capability}$"; then
            if [[ -z "$modules" ]]; then
                modules="$identifier"
            else
                modules="${modules}"$'\n'"${identifier}"
            fi
        fi
    done

    if [[ -n "$modules" ]]; then
        echo "$modules"
    fi

    return 0
}

# Get all registered capabilities
# Usage: get_capabilities
# Returns: List of all capabilities from all modules, one per line (deduplicated)
get_capabilities() {
    local identifier
    local all_capabilities=""
    
    for identifier in "${!MODULE_REGISTRY[@]}"; do
        # Get module metadata
        local metadata="${MODULE_METADATA[$identifier]}"
        
        if [[ -z "$metadata" ]]; then
            continue
        fi

        # Extract capabilities from metadata using grep
        # Capabilities are stored as capabilities_0=..., capabilities_1=..., etc.
        local capabilities
        capabilities=$(echo "$metadata" | grep "^capabilities_[0-9]*=" | sed 's/^capabilities_[0-9]*=//')
        
        # Add capabilities to the list
        if [[ -n "$capabilities" ]]; then
            if [[ -z "$all_capabilities" ]]; then
                all_capabilities="$capabilities"
            else
                all_capabilities="${all_capabilities}"$'\n'"${capabilities}"
            fi
        fi
    done

    # Deduplicate and sort capabilities
    if [[ -n "$all_capabilities" ]]; then
        echo "$all_capabilities" | sort -u
    fi

    return 0
}

