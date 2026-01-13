#!/usr/bin/env bash

# Suite Grouping Functions
# Implements adaptive detection strategies for grouping test files into suites
# No external dependencies

# Source required dependencies
source "src/data_access.sh" 2>/dev/null || true

# Check if configuration file exists
# Usage: has_configuration_file <project_root>
# Returns: 0 if config file exists, 1 otherwise
# Outputs: "suitey.toml" or ".suiteyrc" if found
has_configuration_file() {
    local project_root="$1"
    
    if [[ -z "$project_root" ]] || [[ ! -d "$project_root" ]]; then
        return 1
    fi
    
    if [[ -f "$project_root/suitey.toml" ]]; then
        echo "suitey.toml"
        return 0
    elif [[ -f "$project_root/.suiteyrc" ]]; then
        echo ".suiteyrc"
        return 0
    fi
    
    return 1
}

# Parse TOML configuration file (simplified parser for suitey.toml)
# Usage: parse_toml_config <config_file>
# Returns: Suite definitions in flat data format
# Note: This is a simplified TOML parser that handles only the subset needed for Suitey
parse_toml_config() {
    local config_file="$1"
    
    if [[ -z "$config_file" ]] || [[ ! -f "$config_file" ]]; then
        return 1
    fi
    
    local suites_count=0
    local suite_index=0
    local in_suite=false
    local current_suite_name=""
    local current_suite_files=()
    local result=""
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Check for suite table array start: [[suites]]
        if [[ "$line" =~ ^\[\[suites\]\] ]]; then
            # Save previous suite if we were in one
            if [[ "$in_suite" == true ]] && [[ -n "$current_suite_name" ]] && [[ ${#current_suite_files[@]} -gt 0 ]]; then
                result=$(data_set "$result" "suites_${suite_index}_name" "$current_suite_name")
                local file_idx=0
                for file_pattern in "${current_suite_files[@]}"; do
                    result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file_pattern")
                    ((file_idx++))
                done
                result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_idx")
                ((suite_index++))
                ((suites_count++))
            fi
            
            # Start new suite
            in_suite=true
            current_suite_name=""
            current_suite_files=()
            continue
        fi
        
        # If we're in a suite, parse fields
        if [[ "$in_suite" == true ]]; then
            # Parse name = "value"
            if [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*\"(.*)\" ]]; then
                current_suite_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*\'([^\']*)\' ]]; then
                current_suite_name="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^name[[:space:]]*=[[:space:]]*([^[:space:]]+) ]]; then
                current_suite_name="${BASH_REMATCH[1]}"
            fi
            
            # Parse files = ["pattern1", "pattern2"]
            if [[ "$line" =~ ^files[[:space:]]*=[[:space:]]*\[ ]]; then
                # Multi-line array - collect until closing bracket
                local array_content="${line#*\[}"
                array_content="${array_content%\]}"
                
                # Extract quoted strings
                while [[ "$array_content" =~ \"([^\"]+)\" ]]; do
                    current_suite_files+=("${BASH_REMATCH[1]}")
                    array_content="${array_content#*\"${BASH_REMATCH[1]}\"}"
                    array_content="${array_content#*,}"
                    array_content="${array_content#"${array_content%%[![:space:]]*}"}"
                done
            fi
            
            # Check if we've hit another section (starts with [)
            if [[ "$line" =~ ^\[ ]]; then
                # Save current suite
                if [[ -n "$current_suite_name" ]] && [[ ${#current_suite_files[@]} -gt 0 ]]; then
                    result=$(data_set "$result" "suites_${suite_index}_name" "$current_suite_name")
                    local file_idx=0
                    for file_pattern in "${current_suite_files[@]}"; do
                        result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file_pattern")
                        ((file_idx++))
                    done
                    result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_idx")
                    ((suite_index++))
                    ((suites_count++))
                fi
                in_suite=false
                current_suite_name=""
                current_suite_files=()
            fi
        fi
    done < "$config_file"
    
    # Save last suite if we were in one
    if [[ "$in_suite" == true ]] && [[ -n "$current_suite_name" ]] && [[ ${#current_suite_files[@]} -gt 0 ]]; then
        result=$(data_set "$result" "suites_${suite_index}_name" "$current_suite_name")
        local file_idx=0
        for file_pattern in "${current_suite_files[@]}"; do
            result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file_pattern")
            ((file_idx++))
        done
        result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_idx")
        ((suites_count++))
    fi
    
    # Set suites count
    result=$(data_set "$result" "suites_count" "$suites_count")
    
    echo "$result"
    return 0
}

# Check if directory matches conventional test suite names
# Usage: is_conventional_directory <directory_name>
# Returns: 0 if conventional, 1 otherwise
# Outputs: normalized suite name if conventional
is_conventional_directory() {
    local dir_name="$1"
    local normalized_name
    
    case "$dir_name" in
        unit|units)
            echo "unit"
            return 0
            ;;
        integration|integrations)
            echo "integration"
            return 0
            ;;
        e2e|end-to-end|end_to_end)
            echo "e2e"
            return 0
            ;;
        performance|perf)
            echo "performance"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Group test files using convention-based strategy
# Usage: group_by_convention <project_root> <test_files>
# Returns: Grouped suites in flat data format
group_by_convention() {
    local project_root="$1"
    local test_files="$2"
    
    if [[ -z "$test_files" ]]; then
        echo "suites_count=0"
        return 0
    fi
    
    local suites_count=0
    local suite_index=0
    local result=""
    
    # Group files by their parent directory if it's conventional
    declare -A suite_files
    
    while IFS= read -r file || [[ -n "$file" ]]; do
        if [[ -z "$file" ]]; then
            continue
        fi
        
        # Get directory name
        local file_dir
        file_dir=$(dirname "$file")
        file_dir="${file_dir#$project_root/}"
        
        # Check each level of the path for conventional names
        local suite_name=""
        local path_parts
        IFS='/' read -ra path_parts <<< "$file_dir"
        
        for part in "${path_parts[@]}"; do
            if is_conventional_directory "$part" >/dev/null 2>&1; then
                suite_name=$(is_conventional_directory "$part")
                break
            fi
        done
        
        # If no conventional name found, use directory basename
        if [[ -z "$suite_name" ]]; then
            suite_name=$(basename "$file_dir")
            if [[ -z "$suite_name" ]] || [[ "$suite_name" == "." ]]; then
                suite_name="default"
            fi
        fi
        
        # Add file to suite
        if [[ -z "${suite_files[$suite_name]}" ]]; then
            suite_files[$suite_name]="$file"
        else
            suite_files[$suite_name]="${suite_files[$suite_name]}"$'\n'"$file"
        fi
    done <<< "$test_files"
    
    # Convert to flat data format
    for suite_name in "${!suite_files[@]}"; do
        local files_list="${suite_files[$suite_name]}"
        local file_count=0
        local file_idx=0
        
        result=$(data_set "$result" "suites_${suite_index}_name" "$suite_name")
        
        while IFS= read -r file || [[ -n "$file" ]]; do
            if [[ -n "$file" ]]; then
                result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file")
                ((file_idx++))
                ((file_count++))
            fi
        done <<< "$files_list"
        
        result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_count")
        ((suite_index++))
        ((suites_count++))
    done
    
    result=$(data_set "$result" "suites_count" "$suites_count")
    echo "$result"
    return 0
}

# Group test files by subdirectory structure (preserves user organization)
# Usage: group_by_subdirectory <project_root> <test_files>
# Returns: Grouped suites in flat data format
group_by_subdirectory() {
    local project_root="$1"
    local test_files="$2"
    
    if [[ -z "$test_files" ]]; then
        echo "suites_count=0"
        return 0
    fi
    
    local suites_count=0
    local suite_index=0
    local result=""
    declare -A suite_files
    
    while IFS= read -r file || [[ -n "$file" ]]; do
        if [[ -z "$file" ]]; then
            continue
        fi
        
        # Get relative directory path
        local file_dir
        file_dir=$(dirname "$file")
        file_dir="${file_dir#$project_root/}"
        
        # Use the directory path as suite name (normalize)
        local suite_name="$file_dir"
        if [[ -z "$suite_name" ]] || [[ "$suite_name" == "." ]]; then
            suite_name="root"
        fi
        
        # Normalize path separators
        suite_name="${suite_name//\//_}"
        
        # Add file to suite
        if [[ -z "${suite_files[$suite_name]}" ]]; then
            suite_files[$suite_name]="$file"
        else
            suite_files[$suite_name]="${suite_files[$suite_name]}"$'\n'"$file"
        fi
    done <<< "$test_files"
    
    # Convert to flat data format
    for suite_name in "${!suite_files[@]}"; do
        local files_list="${suite_files[$suite_name]}"
        local file_count=0
        local file_idx=0
        
        result=$(data_set "$result" "suites_${suite_index}_name" "$suite_name")
        
        while IFS= read -r file || [[ -n "$file" ]]; do
            if [[ -n "$file" ]]; then
                result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file")
                ((file_idx++))
                ((file_count++))
            fi
        done <<< "$files_list"
        
        result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_count")
        ((suite_index++))
        ((suites_count++))
    done
    
    result=$(data_set "$result" "suites_count" "$suites_count")
    echo "$result"
    return 0
}

# Group test files by directory (all files in a directory = one suite)
# Usage: group_by_directory <project_root> <test_files>
# Returns: Grouped suites in flat data format
group_by_directory() {
    local project_root="$1"
    local test_files="$2"
    
    if [[ -z "$test_files" ]]; then
        echo "suites_count=0"
        return 0
    fi
    
    local suites_count=0
    local suite_index=0
    local result=""
    declare -A suite_files
    
    while IFS= read -r file || [[ -n "$file" ]]; do
        if [[ -z "$file" ]]; then
            continue
        fi
        
        # Get directory basename as suite name
        local file_dir
        file_dir=$(dirname "$file")
        local suite_name
        suite_name=$(basename "$file_dir")
        
        if [[ -z "$suite_name" ]] || [[ "$suite_name" == "." ]]; then
            suite_name="root"
        fi
        
        # Add file to suite
        if [[ -z "${suite_files[$suite_name]}" ]]; then
            suite_files[$suite_name]="$file"
        else
            suite_files[$suite_name]="${suite_files[$suite_name]}"$'\n'"$file"
        fi
    done <<< "$test_files"
    
    # Convert to flat data format
    for suite_name in "${!suite_files[@]}"; do
        local files_list="${suite_files[$suite_name]}"
        local file_count=0
        local file_idx=0
        
        result=$(data_set "$result" "suites_${suite_index}_name" "$suite_name")
        
        while IFS= read -r file || [[ -n "$file" ]]; do
            if [[ -n "$file" ]]; then
                result=$(data_set "$result" "suites_${suite_index}_files_${file_idx}" "$file")
                ((file_idx++))
                ((file_count++))
            fi
        done <<< "$files_list"
        
        result=$(data_set "$result" "suites_${suite_index}_files_count" "$file_count")
        ((suite_index++))
        ((suites_count++))
    done
    
    result=$(data_set "$result" "suites_count" "$suites_count")
    echo "$result"
    return 0
}

# Group test files by file (each file = one suite)
# Usage: group_by_file <test_files>
# Returns: Grouped suites in flat data format
group_by_file() {
    local test_files="$1"
    
    if [[ -z "$test_files" ]]; then
        echo "suites_count=0"
        return 0
    fi
    
    local suites_count=0
    local suite_index=0
    local result=""
    
    while IFS= read -r file || [[ -n "$file" ]]; do
        if [[ -z "$file" ]]; then
            continue
        fi
        
        # Use filename (without extension) as suite name
        local suite_name
        suite_name=$(basename "$file")
        suite_name="${suite_name%.*}"
        
        if [[ -z "$suite_name" ]]; then
            suite_name="test_${suite_index}"
        fi
        
        result=$(data_set "$result" "suites_${suite_index}_name" "$suite_name")
        result=$(data_set "$result" "suites_${suite_index}_files_0" "$file")
        result=$(data_set "$result" "suites_${suite_index}_files_count" "1")
        ((suite_index++))
        ((suites_count++))
    done <<< "$test_files"
    
    result=$(data_set "$result" "suites_count" "$suites_count")
    echo "$result"
    return 0
}

# Apply adaptive suite grouping strategy
# Usage: apply_adaptive_grouping <project_root> <test_files>
# Returns: Grouped suites in flat data format
apply_adaptive_grouping() {
    local project_root="$1"
    local test_files="$2"
    
    if [[ -z "$test_files" ]]; then
        echo "suites_count=0"
        return 0
    fi
    
    # Strategy 1: Configuration-Driven (highest priority)
    local config_file
    config_file=$(has_configuration_file "$project_root")
    if [[ $? -eq 0 ]]; then
        local config_suites
        config_suites=$(parse_toml_config "$project_root/$config_file" 2>/dev/null)
        if [[ $? -eq 0 ]] && [[ -n "$config_suites" ]]; then
            local config_suites_count
            config_suites_count=$(data_get "$config_suites" "suites_count")
            if [[ -n "$config_suites_count" ]] && [[ "$config_suites_count" -gt 0 ]]; then
                echo "$config_suites"
                return 0
            fi
        fi
    fi
    
    # Strategy 2: Convention-Based
    local convention_result
    convention_result=$(group_by_convention "$project_root" "$test_files")
    local convention_count
    convention_count=$(data_get "$convention_result" "suites_count")
    
    # Check if we found conventional directories
    if [[ -n "$convention_count" ]] && [[ "$convention_count" -gt 0 ]]; then
        # Verify we actually grouped by convention (not just default)
        local has_conventional=false
        local i=0
        while [[ $i -lt "$convention_count" ]]; do
            local suite_name
            suite_name=$(data_get "$convention_result" "suites_${i}_name")
            if is_conventional_directory "$suite_name" >/dev/null 2>&1; then
                has_conventional=true
                break
            fi
            ((i++))
        done
        
        if [[ "$has_conventional" == true ]]; then
            echo "$convention_result"
            return 0
        fi
    fi
    
    # Strategy 3: Subdirectory-Aware
    # Check if files are organized in subdirectories
    local has_subdirs=false
    while IFS= read -r file || [[ -n "$file" ]]; do
        if [[ -n "$file" ]]; then
            local file_dir
            file_dir=$(dirname "$file")
            file_dir="${file_dir#$project_root/}"
            if [[ "$file_dir" != "." ]] && [[ "$file_dir" != "$(basename "$file")" ]]; then
                has_subdirs=true
                break
            fi
        fi
    done <<< "$test_files"
    
    if [[ "$has_subdirs" == true ]]; then
        echo "$(group_by_subdirectory "$project_root" "$test_files")"
        return 0
    fi
    
    # Strategy 4: Directory-Based
    local dir_result
    dir_result=$(group_by_directory "$project_root" "$test_files")
    local dir_count
    dir_count=$(data_get "$dir_result" "suites_count")
    
    if [[ -n "$dir_count" ]] && [[ "$dir_count" -gt 0 ]]; then
        echo "$dir_result"
        return 0
    fi
    
    # Strategy 5: File-Level (fallback)
    echo "$(group_by_file "$test_files")"
    return 0
}

