#!/usr/bin/env bash

# Test Counter Functions
# Counts individual tests in test files using platform-specific patterns
# No external dependencies

# Count tests in a BATS file
# Usage: count_bats_tests <file_path>
# Returns: Number of @test annotations found
count_bats_tests() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
        echo "0"
        return 0
    fi
    
    # Count @test annotations (excluding comments and strings)
    # Pattern: @test followed by optional whitespace and quoted string
    local count=0
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Remove leading/trailing whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Check for @test annotation
        if [[ "$line" =~ @test ]]; then
            ((count++))
        fi
    done < "$file_path"
    
    echo "$count"
    return 0
}

# Count tests in a Rust file
# Usage: count_rust_tests <file_path>
# Returns: Number of #[test] functions found
count_rust_tests() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
        echo "0"
        return 0
    fi
    
    local count=0
    local in_test_module=false
    local brace_depth=0
    local test_module_started=false
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Keep original line for pattern matching (don't trim yet)
        local original_line="$line"
        
        # Remove leading/trailing whitespace for empty check
        local trimmed_line="${line#"${line%%[![:space:]]*}"}"
        trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"
        
        # Skip empty lines
        if [[ -z "$trimmed_line" ]]; then
            continue
        fi
        
        # Track brace depth
        local open_braces="${original_line//[^\{]/}"
        local close_braces="${original_line//[^\}]/}"
        brace_depth=$((brace_depth + ${#open_braces} - ${#close_braces}))
        
        # Check if we're entering a test module
        if echo "$original_line" | grep -q '#\[cfg(test)\]'; then
            in_test_module=true
            test_module_started=false
            brace_depth=0  # Reset depth when entering test module
            continue
        fi
        
        # Check if we've entered the mod block after #[cfg(test)]
        if [[ "$in_test_module" == true ]] && echo "$original_line" | grep -q '^[[:space:]]*mod[[:space:]]'; then
            test_module_started=true
            continue
        fi
        
        # Count #[test] annotations (allow whitespace before #[test])
        # For integration tests (tests/ directory), count all #[test] regardless of module
        # For unit tests (src/ directory), only count if in #[cfg(test)] module
        if echo "$original_line" | grep -q '#\[test\]'; then
            # If file is in tests/ directory, always count
            if [[ "$file_path" =~ /tests/ ]]; then
                ((count++))
            elif [[ "$in_test_module" == true ]] && [[ "$test_module_started" == true ]]; then
                # If in test module and mod block has started, count it
                ((count++))
            fi
        fi
        
        # Check if we're leaving the test module (brace depth back to 0 or negative)
        if [[ "$in_test_module" == true ]] && [[ "$test_module_started" == true ]] && [[ $brace_depth -le 0 ]]; then
            in_test_module=false
            test_module_started=false
        fi
    done < "$file_path"
    
    echo "$count"
    return 0
}

# Count tests in a file based on file extension
# Usage: count_tests_in_file <file_path>
# Returns: Number of tests found
count_tests_in_file() {
    local file_path="$1"
    
    if [[ -z "$file_path" ]] || [[ ! -f "$file_path" ]]; then
        echo "0"
        return 0
    fi
    
    # Determine file type by extension
    local extension="${file_path##*.}"
    
    case "$extension" in
        bats)
            count_bats_tests "$file_path"
            ;;
        rs)
            count_rust_tests "$file_path"
            ;;
        *)
            # Unknown file type, return 0
            echo "0"
            ;;
    esac
}

# Count total tests in multiple files
# Usage: count_tests_in_files <file1> [file2] [file3] ...
# Returns: Total count of tests across all files
count_tests_in_files() {
    local total=0
    
    for file_path in "$@"; do
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            local file_count
            file_count=$(count_tests_in_file "$file_path")
            total=$((total + file_count))
        fi
    done
    
    echo "$total"
    return 0
}

# Count tests for a suite (given suite data in flat format)
# Usage: count_tests_for_suite <suite_data> <suite_index>
# Returns: Total test count for the suite
count_tests_for_suite() {
    local suite_data="$1"
    local suite_index="$2"
    
    if [[ -z "$suite_data" ]] || [[ -z "$suite_index" ]]; then
        echo "0"
        return 0
    fi
    
    # Source data access functions
    source "src/data_access.sh" 2>/dev/null || true
    
    # Get files count for this suite
    local files_count
    if declare -f data_get >/dev/null 2>&1; then
        files_count=$(data_get "$suite_data" "suites_${suite_index}_files_count" || echo "0")
    else
        files_count=$(echo "$suite_data" | grep "^suites_${suite_index}_files_count=" | cut -d'=' -f2 || echo "0")
    fi
    
    if [[ -z "$files_count" ]] || [[ "$files_count" -eq 0 ]]; then
        echo "0"
        return 0
    fi
    
    # Collect all file paths
    local total=0
    local i=0
    while [[ $i -lt "$files_count" ]]; do
        local file_path
        if declare -f data_get >/dev/null 2>&1; then
            file_path=$(data_get "$suite_data" "suites_${suite_index}_files_${i}" || echo "")
        else
            file_path=$(echo "$suite_data" | grep "^suites_${suite_index}_files_${i}=" | cut -d'=' -f2 || echo "")
        fi
        
        if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
            local file_count
            file_count=$(count_tests_in_file "$file_path")
            total=$((total + file_count))
        fi
        
        ((i++))
    done
    
    echo "$total"
    return 0
}

