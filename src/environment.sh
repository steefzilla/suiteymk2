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
                    echo "    git clone https://github.com/bats-core/bats-support.git tests/bats/unit/test_helper/bats-support" >&2
                    ;;
                "bats-assert")
                    echo "  - bats-assert library:" >&2
                    echo "    git clone https://github.com/bats-core/bats-assert.git tests/bats/unit/test_helper/bats-assert" >&2
                    ;;
            esac
        done

        return 1
    fi
}
