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

# Extract an array element from data by index
# Usage: data_get_array <data> <array_name> <index>
# Returns: Array element value, or empty if not found
# Exit code: 0 on success, 1 on error (invalid inputs)
# Behavior: Constructs key as ${array_name}_${index} and calls data_get()
data_get_array() {
    local data="$1"
    local array_name="$2"
    local index="$3"

    # Validate inputs
    if [[ -z "$data" ]] || [[ -z "$array_name" ]] || [[ -z "$index" ]]; then
        return 1
    fi

    # Validate index is numeric (0-based, non-negative integer)
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    # Construct key as ${array_name}_${index} (e.g., "test_files_0")
    local key="${array_name}_${index}"

    # Call data_get() with the constructed key
    data_get "$data" "$key"
    return $?
}

# Get the count of elements in an array
# Usage: data_array_count <data> <array_name>
# Returns: Array count as integer string, or "0" if not found/invalid
# Exit code: 0 on success, 1 if inputs are empty
# Behavior: Looks for ${array_name}_count key and validates it's numeric
data_array_count() {
    local data="$1"
    local array_name="$2"

    # Validate inputs
    if [[ -z "$data" ]] || [[ -z "$array_name" ]]; then
        return 1
    fi

    # Look for ${array_name}_count key (e.g., "test_files_count")
    local count_key="${array_name}_count"
    local count_value
    count_value=$(data_get "$data" "$count_key")

    # If not found, return "0"
    if [[ -z "$count_value" ]]; then
        echo "0"
        return 0
    fi

    # Validate that the value is numeric (non-negative integer)
    if ! [[ "$count_value" =~ ^[0-9]+$ ]]; then
        echo "0"
        return 0
    fi

    # Return the count
    echo "$count_value"
    return 0
}

# Extract all elements from an array
# Usage: data_get_array_all <data> <array_name>
# Returns: Array elements, one per line (stdout), or empty if array doesn't exist
# Exit code: 0 on success
# Behavior: Gets array count, then iterates from 0 to count-1, calling data_get_array() for each index
data_get_array_all() {
    local data="$1"
    local array_name="$2"

    # Validate inputs (but don't fail - return empty if invalid)
    if [[ -z "$data" ]] || [[ -z "$array_name" ]]; then
        return 0
    fi

    # Get array count using data_array_count()
    local count
    count=$(data_array_count "$data" "$array_name")

    # If count is 0, return empty (no elements to return)
    if [[ "$count" == "0" ]]; then
        return 0
    fi

    # Iterate from 0 to count-1, retrieving each element
    local i=0
    while [[ $i -lt $count ]]; do
        # Get array element at index i using data_get_array()
        local element
        element=$(data_get_array "$data" "$array_name" "$i")
        echo "$element"
        i=$((i + 1))
    done

    return 0
}
