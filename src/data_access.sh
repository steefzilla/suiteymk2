#!/usr/bin/env bash

# Suitey Data Access Functions
# Pure Bash data manipulation utilities for the flat data format
# No external dependencies

# Extract a value from data using a key path
# Usage: data_get <data> <key>
# Returns: Extracted value as string, or empty string if not found
# Exit code: 0 on success, 1 on error (empty inputs)
data_get() {
    local data="$1"
    local key="$2"

    # Validate inputs
    if [[ -z "$data" ]] || [[ -z "$key" ]]; then
        return 1
    fi

    # Search for the first occurrence of key= in the data
    local line
    line=$(echo "$data" | grep -m 1 "^${key}=" || true)

    # If not found, return empty string
    if [[ -z "$line" ]]; then
        echo ""
        return 0
    fi

    # Extract value after the = sign
    local value="${line#${key}=}"

    # Remove surrounding quotes if present (both double and single quotes)
    # This handles values like "quoted value" or 'single quoted'
    if [[ "$value" =~ ^\".*\"$ ]]; then
        # Remove double quotes
        value="${value#\"}"
        value="${value%\"}"
    elif [[ "$value" =~ ^\'.*\'$ ]]; then
        # Remove single quotes
        value="${value#\'}"
        value="${value%\'}"
    fi

    # Output the value
    echo "$value"
    return 0
}
