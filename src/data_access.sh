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

# Set a value in data, creating new data with updated value
# Usage: data_set <data> <key> <value>
# Returns: Updated data string (stdout)
# Exit code: 0 on success, 1 if key is empty
# Behavior: Removes existing key if present, escapes value if needed, appends new key-value pair
data_set() {
    local data="$1"
    local key="$2"
    local value="$3"

    # Validate key is not empty
    if [[ -z "$key" ]]; then
        return 1
    fi

    # Remove existing key if present (including multi-line heredoc blocks)
    # Remove lines matching "^${key}="
    local filtered_data
    filtered_data=$(echo "$data" | grep -v "^${key}=" || true)
    
    # Remove heredoc blocks for this key (lines between "${key}<<EOF" and "EOF")
    local cleaned_data=""
    local in_heredoc=false
    local heredoc_start="${key}<<EOF"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if line starts with heredoc marker
        local line_prefix="${line%%<<*}"
        if [[ "$line_prefix" == "$key" ]] && [[ "$line" == *"<<"* ]]; then
            in_heredoc=true
            continue
        fi
        
        # Check if we're ending a heredoc block
        if [[ "$in_heredoc" == true ]] && [[ "$line" == "EOF" ]]; then
            in_heredoc=false
            continue
        fi
        
        # Only include lines that are not part of a heredoc block
        if [[ "$in_heredoc" == false ]]; then
            if [[ -n "$cleaned_data" ]]; then
                cleaned_data="${cleaned_data}"$'\n'"${line}"
            else
                cleaned_data="${line}"
            fi
        fi
    done <<< "$filtered_data"
    
    # If cleaned_data is empty, use filtered_data
    if [[ -z "$cleaned_data" ]]; then
        cleaned_data="$filtered_data"
    fi

    # Escape value if it contains special characters (spaces, $, `, ", \)
    local escaped_value="$value"
    # Check if value contains special characters that need escaping
    if [[ "$value" =~ [[:space:]] ]] || [[ "$value" =~ \$ ]] || [[ "$value" =~ \` ]] || [[ "$value" =~ \" ]] || [[ "$value" =~ \\ ]]; then
        # Wrap in quotes and escape internal quotes and backslashes
        escaped_value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g')
        escaped_value="\"${escaped_value}\""
    fi

    # Append new key-value pair to data
    local result
    if [[ -n "$cleaned_data" ]]; then
        result="${cleaned_data}"$'\n'"${key}=${escaped_value}"
    else
        result="${key}=${escaped_value}"
    fi

    # Output the updated data
    echo "$result"
    return 0
}

# Append a value to an array
# Usage: data_array_append <data> <array_name> <value>
# Returns: Updated data string with new array element
# Exit code: 0 on success
# Behavior: Gets current count, sets new element at index count, updates count to count+1
data_array_append() {
    local data="$1"
    local array_name="$2"
    local value="$3"

    # Get current array count
    local count
    count=$(data_array_count "$data" "$array_name")
    
    # If count failed or returned error, default to 0
    if [[ $? -ne 0 ]] || [[ -z "$count" ]]; then
        count=0
    fi

    # Set new element at index count using data_set()
    data=$(data_set "$data" "${array_name}_${count}" "$value")

    # Update count to count + 1 using data_set()
    local new_count=$((count + 1))
    data=$(data_set "$data" "${array_name}_count" "$new_count")

    # Return updated data string
    echo "$data"
    return 0
}

# Set an entire array, replacing any existing array entries
# Usage: data_set_array <data> <array_name> <value1> [value2] [value3] ...
# Returns: Updated data string
# Exit code: 0 on success
# Behavior: Removes all existing array entries, adds new entries at sequential indices
data_set_array() {
    local data="$1"
    local array_name="$2"
    shift 2  # Remove first two arguments, leaving only values

    # Get current count to know how many entries to remove
    local old_count
    old_count=$(data_array_count "$data" "$array_name")
    
    # Remove all existing array entries (${array_name}_N= and ${array_name}_count=)
    # Remove entries from 0 to old_count-1
    if [[ "$old_count" -gt 0 ]]; then
        local i=0
        while [[ $i -lt $old_count ]]; do
            # Remove the array element line
            data=$(echo "$data" | grep -v "^${array_name}_${i}=" || true)
            i=$((i + 1))
        done
    fi
    
    # Remove the count line
    data=$(echo "$data" | grep -v "^${array_name}_count=" || true)
    
    # Remove empty lines that might have been created
    data=$(echo "$data" | grep -v "^$" || true)
    
    # If data is now empty or only whitespace, reset it
    if [[ -z "${data// }" ]]; then
        data=""
    fi

    # Add new entries for each value at sequential indices
    local index=0
    local values=("$@")
    
    for value in "${values[@]}"; do
        data=$(data_set "$data" "${array_name}_${index}" "$value")
        index=$((index + 1))
    done

    # Set count to number of values added
    data=$(data_set "$data" "${array_name}_count" "$index")

    # Return updated data string
    echo "$data"
    return 0
}

# Set a multi-line value using heredoc syntax
# Usage: data_set_multiline <data> <key> <value>
# Returns: Updated data string with heredoc syntax
# Exit code: 0 on success
# Behavior: Removes existing heredoc block or regular key=value entry, appends new heredoc block
data_set_multiline() {
    local data="$1"
    local key="$2"
    local value="$3"

    # Validate key is not empty
    if [[ -z "$key" ]]; then
        return 1
    fi

    # Remove existing heredoc block if present (lines between `${key}<<EOF` and `EOF`)
    # Also remove regular key=value entry for this key
    local cleaned_data=""
    local in_heredoc=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if line starts with heredoc marker for this key (e.g., "key<<EOF")
        if [[ "${line%%<<*}" == "$key" ]] && [[ "$line" == *"<<"* ]]; then
            in_heredoc=true
            continue
        fi
        
        # Check if we're ending a heredoc block
        if [[ "$in_heredoc" == true ]] && [[ "$line" == "EOF" ]]; then
            in_heredoc=false
            continue
        fi
        
        # Skip lines that are part of a heredoc block
        if [[ "$in_heredoc" == true ]]; then
            continue
        fi
        
        # Skip regular key=value entry for this key
        if [[ "$line" =~ ^${key}= ]]; then
            continue
        fi
        
        # Include all other lines
        if [[ -n "$cleaned_data" ]]; then
            cleaned_data="${cleaned_data}"$'\n'"${line}"
        else
            cleaned_data="${line}"
        fi
    done <<< "$data"
    
    # If cleaned_data is empty, reset it
    if [[ -z "${cleaned_data// }" ]]; then
        cleaned_data=""
    fi

    # Append new heredoc block: `${key}<<EOF`, value lines, `EOF`
    local result
    if [[ -n "$cleaned_data" ]]; then
        result="${cleaned_data}"$'\n'"${key}<<EOF"
    else
        result="${key}<<EOF"
    fi
    
    # Add value lines if not empty
    if [[ -n "$value" ]]; then
        result="${result}"$'\n'"${value}"
    fi
    
    # Add EOF marker
    result="${result}"$'\n'"EOF"

    # Output the updated data
    echo "$result"
    return 0
}

# Get a multi-line value, handling heredoc syntax
# Usage: data_get_multiline <data> <key>
# Returns: Multi-line value (without heredoc markers), or single-line value
# Exit code: 0 on success, 1 on error (invalid inputs)
# Behavior: Checks if key uses heredoc syntax, extracts content between markers or calls data_get()
data_get_multiline() {
    local data="$1"
    local key="$2"

    # Validate inputs
    if [[ -z "$data" ]] || [[ -z "$key" ]]; then
        return 1
    fi

    # Check if key uses heredoc syntax (`${key}<<EOF`)
    local in_heredoc=false
    local heredoc_content=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Check if line starts with heredoc marker for this key (e.g., "key<<EOF")
        if [[ "${line%%<<*}" == "$key" ]] && [[ "$line" == *"<<"* ]]; then
            in_heredoc=true
            continue
        fi
        
        # Check if we're ending a heredoc block
        if [[ "$in_heredoc" == true ]] && [[ "$line" == "EOF" ]]; then
            # Found complete heredoc block, return content
            echo "$heredoc_content"
            return 0
        fi
        
        # Collect content between heredoc markers
        if [[ "$in_heredoc" == true ]]; then
            if [[ -n "$heredoc_content" ]]; then
                heredoc_content="${heredoc_content}"$'\n'"${line}"
            else
                heredoc_content="${line}"
            fi
        fi
    done <<< "$data"
    
    # If we were in a heredoc but didn't find EOF, return what we collected
    if [[ "$in_heredoc" == true ]]; then
        echo "$heredoc_content"
        return 0
    fi
    
    # If not heredoc, call data_get() for regular single-line value
    data_get "$data" "$key"
    return $?
}
