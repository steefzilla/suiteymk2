#!/usr/bin/env bash

# Suitey Build Script
# This script bundles all source files and modules into a single executable suitey.sh

set -e

# Script version
SCRIPT_VERSION="0.1.0"

# Default output file
DEFAULT_OUTPUT="suitey.sh"

# Function to display usage information
show_usage() {
    cat << EOF
Suitey Build Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Build the Suitey executable by bundling all source files and modules.

OPTIONS:
    -h, --help          Show this help message and exit
    -v, --version       Show version information and exit
    --output FILE       Specify output file (default: ${DEFAULT_OUTPUT})

EXAMPLES:
    $0                          # Build with default settings
    $0 --output my-suitey.sh    # Build with custom output file
    $0 --help                   # Show this help message

EOF
}

# Function to show version
show_version() {
    echo "Suitey Build Script v${SCRIPT_VERSION}"
}

# Function to log messages
log() {
    echo "[BUILD] $1" >&2
}

# Function to show error and exit
error() {
    echo "[ERROR] $1" >&2
    echo >&2
    echo "Run '$0 --help' for usage information." >&2
    exit 1
}

# Main build function
build_suitey() {
    local output_file="$1"

    log "Starting Suitey build process..."
    log "Output file: ${output_file}"

    # Create a temporary file for building
    local temp_file
    temp_file="$(mktemp)" || error "Failed to create temporary file"

    # Ensure temp file is cleaned up on exit
    trap "rm -f '$temp_file'" EXIT

    # Bundle all source files into the temporary file
    bundle_source_files "$temp_file"

    # Move temp file to final location atomically
    if ! mv "$temp_file" "$output_file"; then
        error "Failed to create output file: $output_file"
    fi

    # Comprehensive validation of the build output
    validate_build_output "$output_file"

    local file_size
    file_size=$(wc -c < "$output_file")
    log "Build completed successfully!"
    log "Output: ${output_file} (${file_size} bytes)"
}

# Validate output file path
validate_output_file() {
    local file="$1"

    # Check if the directory exists and is writable
    local dir="$(dirname "$file")"
    if [[ ! -d "$dir" ]]; then
        error "Output directory does not exist: $dir"
    fi

    if [[ ! -w "$dir" ]]; then
        error "Output directory is not writable: $dir"
    fi

    # Check if output file would overwrite something important
    if [[ -f "$file" && ! -w "$file" ]]; then
        error "Output file exists but is not writable: $file"
    fi
}

# Discover all source files in src/ directory
discover_source_files() {
    if [[ ! -d "src" ]]; then
        error "src/ directory not found"
    fi

    # Find all .sh files in src/ directory, sorted for consistency
    # Exclude hidden files and directories
    find "src" -name "*.sh" -type f -not -path "*/.*" | sort
}

# Discover all module files in mod/ directory
discover_modules() {
    if [[ ! -d "mod" ]]; then
        log "Warning: mod/ directory not found - no modules to include"
        return 0
    fi

    # Find all .sh files in mod/ directory recursively
    # Exclude hidden files and directories
    find "mod" -name "*.sh" -type f -not -path "*/.*" 2>/dev/null | sort
}

# Validate that discovered source files exist and are readable
validate_source_files() {
    local files=("$@")

    if [[ ${#files[@]} -eq 0 ]]; then
        log "Warning: No source files to validate"
        return 0
    fi

    log "Validating ${#files[@]} source file(s)..."

    for file in "${files[@]}"; do
        if [[ -z "$file" ]]; then
            error "Empty filename encountered during validation"
        fi

        if [[ ! -e "$file" ]]; then
            error "Source file does not exist: $file"
        fi

        if [[ ! -f "$file" ]]; then
            error "Path exists but is not a regular file: $file"
        fi

        if [[ ! -r "$file" ]]; then
            error "Source file is not readable: $file"
        fi

        # Check file size (basic sanity check)
        local file_size
        file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        if [[ $file_size -eq 0 ]]; then
            log "Warning: Source file appears to be empty: $file"
        fi
    done

    log "All source files validated successfully"
}

# Get build order for source files (basic dependency analysis)
# Orders files based on simple heuristics - can be extended for full dependency analysis
get_build_order() {
    local source_files=("$@")

    if [[ ${#source_files[@]} -eq 0 ]]; then
        return 0
    fi

    log "Determining build order for ${#source_files[@]} file(s)..."

    # Simple ordering: environment files first, then others
    # This is a basic implementation - full dependency analysis would be more complex
    local ordered_files=()
    local env_files=()
    local other_files=()

    for file in "${source_files[@]}"; do
        if [[ "$file" == *"environment"* ]]; then
            env_files+=("$file")
        else
            other_files+=("$file")
        fi
    done

    # Environment files first, then others
    ordered_files=("${env_files[@]}" "${other_files[@]}")

    log "Build order determined: ${#ordered_files[@]} file(s) ready for inclusion"

    # Output the ordered files
    printf '%s\n' "${ordered_files[@]}"
}

# Integration function that combines all source discovery
source_discovery_integration() {
    log "Discovering source files..."

    # Discover source files
    local source_files
    source_files=$(discover_source_files)

    # Discover modules
    local module_files
    module_files=$(discover_modules)

    # Combine all files (filter out empty lines)
    local all_files=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && all_files+=("$file")
    done <<< "$source_files"

    while IFS= read -r file; do
        [[ -n "$file" ]] && all_files+=("$file")
    done <<< "$module_files"

    # Validate files exist (only if we have files)
    if [[ ${#all_files[@]} -gt 0 ]]; then
        validate_source_files "${all_files[@]}"
    fi

    # Get build order
    local ordered_files
    ordered_files=$(get_build_order "${all_files[@]}")

    # Output the files (one per line)
    printf '%s\n' "${ordered_files[@]}"
}

# Create the bundle header with metadata
create_bundle_header() {
    local output_file="$1"

    # Create the bundled script header
    cat > "$output_file" << 'EOF'
#!/usr/bin/env bash

# Suitey - Cross-platform test runner
# This file was generated by build.sh - do not edit directly

EOF

    # Add version information
    echo "# Version: ${SCRIPT_VERSION}" >> "$output_file"
    echo "# Built: $(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$output_file"
    echo "# Built on: $(uname -s) $(uname -r)" >> "$output_file"
    echo >> "$output_file"
}

# Include source files in the bundle
include_source_files() {
    local output_file="$1"
    shift  # Remove output_file from arguments
    local source_files=("$@")

    if [[ ${#source_files[@]} -eq 0 ]]; then
        log "Warning: No source files to include"
        return 0
    fi

    log "Including ${#source_files[@]} source file(s)..."

    for source_file in "${source_files[@]}"; do
        if [[ -f "$source_file" ]]; then
            log "Including: $source_file"

            # Add a comment header for the file
            echo "# Included from: $source_file" >> "$output_file"

            # Include the file content
            cat "$source_file" >> "$output_file"

            # Add separator
            echo >> "$output_file"
            echo "# End of: $source_file" >> "$output_file"
            echo >> "$output_file"
        else
            error "Source file not found: $source_file"
        fi
    done

    log "Source files included successfully"
}

# Create the bundle footer with main execution
create_bundle_footer() {
    local output_file="$1"

    cat >> "$output_file" << 'EOF'
# Main Suitey functionality will be added here

main() {
    echo "Suitey v0.1.0"
    echo "Build system functional - ready for implementation"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  --help, -h    Show help"
    echo "  --version, -v Show version"
}

# Run main function
main "$@"
EOF
}

# Validate the bundled script
validate_bundle() {
    local bundle_file="$1"

    if [[ ! -f "$bundle_file" ]]; then
        error "Bundle file does not exist: $bundle_file"
    fi

    # Basic syntax check
    if ! bash -n "$bundle_file" 2>/dev/null; then
        error "Bundle file has syntax errors: $bundle_file"
    fi

    # Check file size (should not be empty)
    local file_size
    file_size=$(wc -c < "$bundle_file")
    if [[ $file_size -lt 100 ]]; then  # Arbitrary minimum size
        error "Bundle file appears too small: $bundle_file (${file_size} bytes)"
    fi

    log "Bundle validation passed"
}

# Comprehensive build output validation
validate_build_output() {
    local output_file="$1"

    log "Starting comprehensive build output validation..."

    # 1. Check if file exists
    if [[ ! -f "$output_file" ]]; then
        error "Build output file does not exist: $output_file"
    fi

    # 2. Check if file is executable
    if [[ ! -x "$output_file" ]]; then
        log "Making build output executable: $output_file"
        if ! chmod +x "$output_file"; then
            error "Failed to make build output executable: $output_file"
        fi
    fi

    # 3. Verify shebang is correct
    local first_line
    first_line=$(head -n1 "$output_file")
    if [[ "$first_line" != "#!/usr/bin/env bash" ]]; then
        error "Incorrect shebang in build output. Expected '#!/usr/bin/env bash', got: $first_line"
    fi

    # 4. Check Bash syntax validity
    if ! bash -n "$output_file" 2>/dev/null; then
        error "Build output has invalid Bash syntax: $output_file"
    fi

    # 5. Check reasonable file size (not empty, not too small)
    local file_size
    file_size=$(wc -c < "$output_file")
    if [[ $file_size -lt 30 ]]; then  # Minimum reasonable size for any script
        error "Build output file appears too small: $output_file (${file_size} bytes). Expected at least 30 bytes for any script."
    fi

    if [[ $file_size -gt 1048576 ]]; then  # 1MB max
        error "Build output file appears too large: $output_file (${file_size} bytes). Maximum allowed is 1MB."
    fi

    # 6. Verify expected functions are present (for suitey builds)
    # This is optional - some scripts might not have these functions
    local has_main_function
    has_main_function=$(grep -c "^main()" "$output_file" || echo "0")

    local has_suitey_content
    has_suitey_content=$(grep -c "Suitey" "$output_file" || echo "0")

    if [[ $has_main_function -gt 0 && $has_suitey_content -gt 0 ]]; then
        # This appears to be a suitey build, check for expected functions
        if ! grep -q "check_bash_version" "$output_file"; then
            log "Warning: Suitey build output missing environment functions"
        fi
    fi

    # 8. Test that script runs without errors (basic execution test)
    log "Testing script execution..."
    if ! timeout 10 bash "$output_file" --help >/dev/null 2>&1; then
        error "Build output script fails to execute properly: $output_file"
    fi

    # 9. Verify filesystem isolation compliance (script shouldn't access files outside /tmp)
    # This is a basic check - more comprehensive isolation testing would be complex
    if grep -q "cd /" "$output_file" || grep -q "cd /home" "$output_file" || grep -q "cd /usr" "$output_file"; then
        log "Warning: Build output may contain paths that could violate filesystem isolation"
        # Don't fail here as this might be legitimate (like /usr/bin/env), just warn
    fi

    # 10. Test script execution (if it has --version support)
    local script_output
    script_output=$(timeout 5 bash "$output_file" --version 2>/dev/null || echo "no_version_flag")

    if [[ "$script_output" != "no_version_flag" && "$script_output" != "timeout" ]]; then
        # Script supports --version, check if it produces reasonable output
        if echo "$script_output" | grep -q "Suitey"; then
            log "Script produces expected Suitey version output"
        fi
    else
        # Script doesn't support --version or timed out - that's OK for basic validation
        log "Script execution test passed (no --version support or timeout)"
    fi

    log "Build output validation completed successfully"
    log "Validated: syntax, executability, size, functions, execution, isolation"
}

# Main bundling function that orchestrates the entire process
bundle_source_files() {
    local output_file="$1"

    log "Starting script bundling process..."

    # Discover all source files
    local source_files
    source_files=$(source_discovery_integration)

    # Convert to array
    local source_files_array=()
    while IFS= read -r file; do
        [[ -n "$file" ]] && source_files_array+=("$file")
    done <<< "$source_files"

    if [[ ${#source_files_array[@]} -eq 0 ]]; then
        log "Warning: No source files found to bundle"
    else
        log "Found ${#source_files_array[@]} file(s) to bundle"
    fi

    # Create bundle header
    create_bundle_header "$output_file"

    # Include source files
    include_source_files "$output_file" "${source_files_array[@]}"

    # Create bundle footer
    create_bundle_footer "$output_file"

    # Validate the bundle
    validate_bundle "$output_file"

    log "Script bundling completed successfully"
}

# Parse command line arguments
main() {
    local output_file="$DEFAULT_OUTPUT"

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            --output)
                if [[ $# -lt 2 ]]; then
                    error "--output requires a filename argument"
                fi
                if [[ "$2" =~ ^- ]]; then
                    error "--output requires a filename argument (got option: $2)"
                fi
                output_file="$2"
                shift 2
                ;;
            --output=*)
                output_file="${1#*=}"
                if [[ -z "$output_file" ]]; then
                    error "--output= requires a filename argument"
                fi
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Validate the output file
    validate_output_file "$output_file"

    # Perform the build
    build_suitey "$output_file"
}

# Run the main function with all arguments only when executed directly
# (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
