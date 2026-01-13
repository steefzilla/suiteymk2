#!/bin/bash
# setup.sh - Initialize Suitey repository and dependencies

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check if we're in the right directory
check_repository() {
    if [[ ! -f "IMPLEMENTATION-PLAN.md" ]] || [[ ! -d "src" ]] || [[ ! -d "tests" ]]; then
        error "This script must be run from the Suitey repository root directory"
        exit 1
    fi
}

# Initialize git submodules
setup_submodules() {
    log "Initializing git submodules..."

    if [[ -f ".gitmodules" ]]; then
        git submodule update --init --recursive
        success "Git submodules initialized"
    else
        warning "No .gitmodules file found - skipping submodule initialization"
    fi
}

# Check for required tools
check_dependencies() {
    log "Checking for required tools..."

    local missing_tools=()

    # Check for git
    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi

    # Check for bats (optional for basic setup)
    if ! command -v bats &> /dev/null; then
        warning "BATS test framework not found. Install with:"
        echo "  Ubuntu/Debian: sudo apt-get install bats"
        echo "  macOS: brew install bats-core"
        echo "  npm: npm install -g bats"
    else
        success "BATS test framework found: $(bats --version)"
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi

    success "All required tools are available"
}

# Verify test setup
verify_test_setup() {
    log "Verifying test setup..."

    # Check if test helper libraries exist
    local helpers=(
        "tests/bats/test_helper/bats-support/load.bash"
        "tests/bats/test_helper/bats-assert/load.bash"
    )

    local missing_helpers=()
    for helper in "${helpers[@]}"; do
        if [[ ! -f "$helper" ]]; then
            missing_helpers+=("$helper")
        fi
    done

    if [[ ${#missing_helpers[@]} -gt 0 ]]; then
        error "Test helper libraries are missing:"
        for helper in "${missing_helpers[@]}"; do
            echo "  - $helper"
        done
        echo ""
        echo "Try running: git submodule update --init --recursive"
        exit 1
    fi

    success "All test helper libraries are available"
}

# Show usage instructions
show_usage() {
    echo ""
    echo "Repository setup complete! 🎉"
    echo ""
    echo "Next steps:"
    echo "  • Build the project: ./build.sh"
    echo "  • Run unit tests:    bats tests/bats/unit/"
    echo "  • Run all tests:     bats tests/bats/"
    echo ""
    echo "For more information, see:"
    echo "  • spec/TESTING.md - Testing documentation"
    echo "  • IMPLEMENTATION-PLAN.md - Project details"
}

# Main setup function
main() {
    echo "Suitey Repository Setup"
    echo "======================="
    echo ""

    check_repository
    setup_submodules
    check_dependencies
    verify_test_setup
    show_usage
}

# Run main function
main "$@"
