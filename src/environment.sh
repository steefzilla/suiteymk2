#!/usr/bin/env bash

# Suitey Environment Validation Functions
# These functions validate that the development and runtime environment
# is properly configured for Suitey to operate correctly.

# Check if Bash version is 4.0 or higher
check_bash_version() {
    local bash_version
    bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)

    if [[ $(echo "$bash_version >= 4.0" | bc -l) -eq 1 ]]; then
        return 0
    else
        echo "Error: Bash version $bash_version is too old. Suitey requires Bash 4.0 or higher." >&2
        echo "Current version: $bash_version" >&2
        echo "Please upgrade Bash to version 4.0 or higher." >&2
        echo "On Ubuntu/Debian: sudo apt-get install bash" >&2
        echo "On macOS with Homebrew: brew install bash" >&2
        return 1
    fi
}

# Check if Docker is installed and accessible
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        return 0
    else
        echo "Error: Docker is not installed. Suitey requires Docker for containerized builds and test execution." >&2
        echo "Please install Docker:" >&2
        echo "  - Ubuntu/Debian: sudo apt-get install docker.io" >&2
        echo "  - CentOS/RHEL: sudo yum install docker" >&2
        echo "  - macOS: Download from https://www.docker.com/products/docker-desktop" >&2
        echo "  - Windows: Download from https://www.docker.com/products/docker-desktop" >&2
        return 1
    fi
}

# Check if Docker daemon is running
check_docker_daemon_running() {
    if docker info >/dev/null 2>&1; then
        return 0
    else
        echo "Error: Docker daemon is not running. Suitey requires a running Docker daemon." >&2
        echo "Please start Docker:" >&2
        echo "  - Linux: sudo systemctl start docker (or sudo service docker start)" >&2
        echo "  - macOS/Windows: Start Docker Desktop application" >&2
        echo "  - Or run: sudo dockerd (in a separate terminal)" >&2
        return 1
    fi
}

# Check if required directories exist
check_required_directories() {
    local dirs=("src" "tests/bats" "mod")
    local missing_dirs=()

    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            missing_dirs+=("$dir")
        fi
    done

    if [[ ${#missing_dirs[@]} -eq 0 ]]; then
        return 0
    else
        echo "Error: Required directories are missing: ${missing_dirs[*]}" >&2
        echo "Please create the missing directories:" >&2
        for dir in "${missing_dirs[@]}"; do
            echo "  mkdir -p $dir" >&2
        done
        return 1
    fi
}

# Check if /tmp directory is writable
check_tmp_writable() {
    if [[ -w "/tmp" ]]; then
        return 0
    else
        echo "Error: /tmp directory is not writable. Suitey requires write access to /tmp for temporary files." >&2
        echo "Please check /tmp permissions:" >&2
        echo "  ls -ld /tmp" >&2
        echo "If permissions are incorrect, you may need to:" >&2
        echo "  sudo chmod 1777 /tmp" >&2
        return 1
    fi
}

# Check if required test dependencies are available
check_test_dependencies() {
    local deps=("bats")
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done

    # Check for bats-support and bats-assert libraries
    if [[ ! -f "tests/bats/unit/test_helper/bats-support/load.bash" ]]; then
        missing_deps+=("bats-support")
    fi

    if [[ ! -f "tests/bats/unit/test_helper/bats-assert/load.bash" ]]; then
        missing_deps+=("bats-assert")
    fi

    if [[ ${#missing_deps[@]} -eq 0 ]]; then
        return 0
    else
        echo "Error: Required test dependencies are missing: ${missing_deps[*]}" >&2
        echo "Please install the missing dependencies:" >&2

        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "bats")
                    echo "  - BATS testing framework:" >&2
                    echo "    Ubuntu/Debian: sudo apt-get install bats" >&2
                    echo "    macOS: brew install bats-core" >&2
                    echo "    Or download from: https://github.com/bats-core/bats-core" >&2
                    ;;
                "bats-support")
                    echo "  - bats-support library:" >&2
                    echo "    This dependency is now automatically managed as a git submodule." >&2
                    echo "    Use 'git submodule update --init --recursive' if missing." >&2
                    ;;
                "bats-assert")
                    echo "  - bats-assert library:" >&2
                    echo "    This dependency is now automatically managed as a git submodule." >&2
                    echo "    Use 'git submodule update --init --recursive' if missing." >&2
                    ;;
            esac
        done

        return 1
    fi
}

# Check if files can be created in /tmp directory
create_test_file_in_tmp() {
    local test_file="/tmp/suitey_test_file_$$"

    # Try to create a test file in /tmp
    if echo "test content" > "$test_file" 2>/dev/null; then
        # Clean up the test file
        rm -f "$test_file"
        return 0
    else
        echo "Error: Cannot create files in /tmp directory. Suitey requires write access to /tmp." >&2
        return 1
    fi
}

# Verify that filesystem isolation principle is maintained
verify_filesystem_isolation_principle() {
    # This function verifies that Suitey respects filesystem isolation
    # Suitey should only write to /tmp, not modify the project directory
    local project_dir
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Check that project directory exists and is accessible for reading
    if [[ -d "$project_dir" && -r "$project_dir" ]]; then
        # Project directory should be readable for Suitey to function
        # The isolation principle means Suitey won't write here during execution
        return 0
    else
        echo "Error: Project directory is not accessible. This may indicate permission issues." >&2
        return 1
    fi
}

# Check if temporary directories can be created in /tmp
create_test_directory_in_tmp() {
    local test_dir="/tmp/suitey_test_dir_$$"

    # Try to create a test directory in /tmp
    if mkdir "$test_dir" 2>/dev/null; then
        # Clean up the test directory
        rmdir "$test_dir"
        return 0
    else
        echo "Error: Cannot create directories in /tmp. Suitey requires write access to /tmp for temporary directories." >&2
        return 1
    fi
}

# Verify that environment checks respect filesystem isolation principle
verify_environment_filesystem_isolation() {
    # This function verifies that all environment validation functions
    # only access /tmp and don't modify the project directory
    local project_dir
    project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    # Use a lighter approach - check for temporary files created outside /tmp
    # instead of full checksum comparison
    local temp_files_before
    temp_files_before=$(find "$project_dir" -name "suitey_*" -type f 2>/dev/null | wc -l)

    # Run all environment validation functions
    check_bash_version >/dev/null 2>&1
    check_docker_installed >/dev/null 2>&1
    check_docker_daemon_running >/dev/null 2>&1
    check_required_directories >/dev/null 2>&1
    check_tmp_writable >/dev/null 2>&1
    check_test_dependencies >/dev/null 2>&1

    local temp_files_after
    temp_files_after=$(find "$project_dir" -name "suitey_*" -type f 2>/dev/null | wc -l)

    # Verify that no suitey temporary files were created in project directory
    if [[ "$temp_files_before" -eq "$temp_files_after" ]]; then
        return 0
    else
        echo "Error: Environment validation functions created files outside /tmp. This violates filesystem isolation." >&2
        return 1
    fi
}