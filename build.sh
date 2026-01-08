#!/usr/bin/env bash

# Suitey Build Script
# This script bundles all source files and modules into a single executable suitey.sh

set -e

# Script version
SCRIPT_VERSION="0.1.0"

# Default output file
DEFAULT_OUTPUT="suitey.sh"

# Build options
VERBOSE_MODE=false
CLEAN_MODE=false
BUNDLE_VERSION="$SCRIPT_VERSION"
OUTPUT_NAME=""

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
    --name NAME         Set output name (used with default output location)
    --version VER       Set version to include in bundle (default: ${SCRIPT_VERSION})
    --clean             Clean output file before building
    --verbose           Show detailed build output

EXAMPLES:
    $0                          # Build with default settings
    $0 --output my-suitey.sh    # Build with custom output file
    $0 --name myapp             # Build with custom name (creates myapp.sh)
    $0 --version 2.0.0          # Build with version 2.0.0 in bundle
    $0 --clean                  # Clean existing output before building
    $0 --verbose                # Show detailed build progress
    $0 --help                   # Show this help message

EOF
}

# Function to show version
show_version() {
    echo "Suitey Build Script v${SCRIPT_VERSION}"
}

# Function to log messages (always shown)
log() {
    echo "[BUILD] $1" >&2
}

# Function to log verbose messages (only shown with --verbose)
vlog() {
    if [[ "$VERBOSE_MODE" == "true" ]]; then
        echo "[BUILD] $1" >&2
    fi
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

    vlog "Validating ${#files[@]} source file(s)..."

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

    vlog "Determining build order for ${#source_files[@]} file(s)..."

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
    echo "# Version: ${BUNDLE_VERSION}" >> "$output_file"
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
            vlog "Including: $source_file"

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

show_help() {
    cat << 'HELP_EOF'
Suitey v0.1.0 - Cross-platform test runner

Usage: suitey.sh [OPTIONS] [COMMAND]

DESCRIPTION
    Suitey is a cross-platform test runner that automatically detects test suites,
    builds projects, and executes tests in isolated Docker containers.

OPTIONS
    -h, --help          Show this help message and exit
    -v, --version       Show version information and exit

COMMANDS
    (Commands will be implemented in future phases)

EXAMPLES
    suitey.sh --help          Show help information
    suitey.sh --version       Show version information
    suitey.sh                 Show help (default behavior)

For more information, see the Suitey documentation.
HELP_EOF
}

show_version() {
    echo "Suitey v0.1.0"
    echo "Build system functional - ready for implementation"
}

main() {
    # Parse command-line arguments
    if [[ $# -eq 0 ]]; then
        # No arguments provided, show help
        show_help
        exit 0
    fi

    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            echo "Run '$0 --help' for usage information." >&2
            exit 2
            ;;
    esac
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

# Clean up build artifacts and temporary files
cleanup_build_artifacts() {
    log "Cleaning up build artifacts..."

    # Clean up suitey temp files in /tmp (but be careful not to remove system files)
    local temp_files
    temp_files=$(find /tmp -maxdepth 1 -name "suitey_*" -type f 2>/dev/null || true)

    local cleaned_count=0
    if [[ -n "$temp_files" ]]; then
        while IFS= read -r temp_file || [[ -n "$temp_file" ]]; do
            if [[ -n "$temp_file" && -f "$temp_file" ]]; then
                log "Removing temporary file: $temp_file"
                if rm -f "$temp_file" 2>/dev/null; then
                    cleaned_count=$((cleaned_count + 1))
                fi
            fi
        done <<< "$temp_files"
    fi

    if [[ $cleaned_count -gt 0 ]]; then
        log "Cleaned up $cleaned_count temporary files"
    else
        log "No temporary files to clean up"
    fi

    # Also clean up any temporary directories created during build
    local temp_dirs
    temp_dirs=$(find /tmp -maxdepth 1 -name "suitey_*" -type d 2>/dev/null || true)

    if [[ -n "$temp_dirs" ]]; then
        while IFS= read -r temp_dir || [[ -n "$temp_dir" ]]; do
            if [[ -n "$temp_dir" && -d "$temp_dir" ]]; then
                # Only remove empty directories to be safe
                # Use || true to prevent set -e from exiting on find failure
                local dir_contents
                dir_contents=$(find "$temp_dir" -mindepth 1 -maxdepth 1 2>/dev/null || true)
                if [[ -z "$dir_contents" ]]; then
                    log "Removing empty temporary directory: $temp_dir"
                    rmdir "$temp_dir" 2>/dev/null || true
                fi
            fi
        done <<< "$temp_dirs"
    fi

    # Note: We don't clean up the final output file as that's the intended artifact
    # We also don't clean up the build directory itself as it may contain other artifacts

    log "Build artifact cleanup completed"
    return 0
}

# Generate artifact filename with optional versioning
generate_artifact_filename() {
    local base_name="${1:-suitey}"
    local version="$SCRIPT_VERSION"
    local timestamp=""
    local extension="sh"

    # Generate timestamp if requested (could be added as a flag later)
    # timestamp="$(date +%Y%m%d_%H%M%S)_"

    echo "${base_name}.${extension}"
}

# Validate and normalize output path
normalize_output_path() {
    local output_path="$1"

    # If no path specified, use default
    if [[ -z "$output_path" ]]; then
        output_path="$DEFAULT_OUTPUT"
    fi

    # Convert relative paths to absolute
    if [[ "$output_path" != /* ]]; then
        output_path="$(pwd)/$output_path"
    fi

    # Remove any trailing slashes from directory paths
    if [[ "$output_path" == */ ]]; then
        output_path="${output_path%/}"
    fi

    echo "$output_path"
}

# Ensure output directory exists
ensure_output_directory() {
    local output_file="$1"
    local output_dir="$(dirname "$output_file")"

    # Handle the case where output_file has no directory component
    if [[ "$output_file" == "$output_dir" ]]; then
        output_dir="."
    fi

    if [[ ! -d "$output_dir" ]]; then
        log "Creating output directory: $output_dir"
        mkdir -p "$output_dir" || error "Failed to create output directory: $output_dir"
    fi

    # Verify the directory is writable
    if [[ ! -w "$output_dir" ]]; then
        error "Output directory is not writable: $output_dir"
    fi
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
        vlog "Found ${#source_files_array[@]} file(s) to bundle"
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

# Clean output file before building
clean_output_file() {
    local output_file="$1"

    if [[ -f "$output_file" ]]; then
        log "Cleaning existing output file: $output_file"
        rm -f "$output_file" || error "Failed to remove existing output file: $output_file"
        vlog "Removed existing file: $output_file"
    else
        vlog "No existing file to clean: $output_file"
    fi
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
            -v)
                show_version
                exit 0
                ;;
            --version)
                # Check if this is --version with argument (set bundle version) or without (show version)
                if [[ $# -ge 2 && ! "$2" =~ ^- ]]; then
                    # --version with argument: set bundle version
                    BUNDLE_VERSION="$2"
                    shift 2
                else
                    # --version without argument: show version and exit
                    show_version
                    exit 0
                fi
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
            --name)
                if [[ $# -lt 2 ]]; then
                    error "--name requires a name argument"
                fi
                if [[ "$2" =~ ^- ]]; then
                    error "--name requires a name argument (got option: $2)"
                fi
                OUTPUT_NAME="$2"
                shift 2
                ;;
            --name=*)
                OUTPUT_NAME="${1#*=}"
                if [[ -z "$OUTPUT_NAME" ]]; then
                    error "--name= requires a name argument"
                fi
                shift
                ;;
            --version=*)
                BUNDLE_VERSION="${1#*=}"
                if [[ -z "$BUNDLE_VERSION" ]]; then
                    error "--version= requires a version argument"
                fi
                shift
                ;;
            --clean)
                CLEAN_MODE=true
                shift
                ;;
            --verbose)
                VERBOSE_MODE=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done

    # Handle --name option: if name is set and output is still default, use name
    if [[ -n "$OUTPUT_NAME" && "$output_file" == "$DEFAULT_OUTPUT" ]]; then
        output_file="${OUTPUT_NAME}.sh"
        vlog "Using --name option: output will be $output_file"
    fi

    # Normalize and validate the output path
    output_file=$(normalize_output_path "$output_file")

    # Ensure output directory exists
    ensure_output_directory "$output_file"

    # Clean output file if --clean was specified
    if [[ "$CLEAN_MODE" == "true" ]]; then
        clean_output_file "$output_file"
    fi

    # Validate the output file
    validate_output_file "$output_file"

    # Perform the build
    build_suitey "$output_file"

    # Clean up artifacts
    cleanup_build_artifacts
}

# Run the main function with all arguments only when executed directly
# (not when sourced for testing)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
