# Suitey Testing Documentation

## Overview

Suitey's test suite provides comprehensive coverage of all components through unit tests (with intelligent mocking) and integration tests (with real Docker operations). The test framework is designed to be safe for parallel execution, maintainable, and easy to extend. All tests respect Suitey's principle of not modifying the host filesystem except for `/tmp`.

## Table of Contents

- [Test Structure](#test-structure)
- [Prerequisites](#prerequisites)
- [Running Tests](#running-tests)
- [Test Guidelines for Parallel Execution](#test-guidelines-for-parallel-execution)
- [Coding Patterns for Testability](#coding-patterns-for-testability)
- [Mock System for Unit Tests](#mock-system-for-unit-tests)
- [Integration Tests](#integration-tests)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)
- [CI/CD Integration](#cicd-integration)

## Test Structure

### Test Categories

#### Unit Tests (`tests/bats/unit/`)
- **Suitey Modules Registry Tests**: Module registration, metadata management, capability indexing
- **Build Manager Tests**: Docker orchestration, container management, build execution (with mocking)
- **Platform Detector Tests**: Platform detection logic
- **Project Scanner Tests**: Project structure analysis
- **Data Access Tests**: Data manipulation utilities
- **Performance Tests**: Concurrency, I/O, memory, startup
- **Security Tests**: Input validation, path traversal, permissions, temp files
- **Static Analysis Tests**: Code quality, complexity, dead code detection

#### Integration Tests (`tests/bats/integration/`)
- **Build Manager Integration**: Real Docker operations, container lifecycle, image building
- **Suitey Modules Registry Integration**: Language detection, project scanning, test suite detection
- **End-to-End Workflows**: Complete test execution flows

### Test Files Organization

```
tests/bats/
├── unit/                    # Unit tests with mocking
│   ├── mod_registry.bats
│   ├── build_manager.bats
│   ├── platform_detector.bats
│   └── ...
├── integration/            # Integration tests with real Docker
│   ├── build_manager.bats
│   ├── mod_platform_detector.bats
│   ├── mod_project_scanner.bats
│   ├── mod_test_suite_detector.bats
│   └── ...
├── helpers/                # Shared test utilities
│   ├── bats-support/       # Official bats support library
│   ├── bats-assert/        # Official bats assertion library
│   ├── common_setup.bash   # Common test setup utilities
│   ├── common_teardown.bash # Common test teardown utilities
│   ├── mock_system.bash    # Mocking system for unit tests
│   ├── mod_registry.bash # Suitey Modules registry test helpers
│   ├── project_scanner.bash # Project scanner test helpers
│   ├── build_manager.bash  # Build manager test helpers
│   └── platform_detector.bash # Platform detector test helpers
├── static/                 # Static analysis tests
│   ├── complexity.bats     # Code complexity checks
│   ├── quality.bats        # Code quality checks
│   └── security.bats       # Security checks
└── utils/                  # Test utilities
    ├── docker_test_utils.bash
    └── performance_test_utils.bash
```

## Prerequisites

### System Requirements
- **Docker**: Required for integration tests that use real containers
- **BATS**: Test framework (installed via `npm install -g bats` or package manager)
- **Bash 4.0+**: Required for test execution
- **Git**: For repository operations in tests

### Test Dependencies
```bash
# Install BATS test framework
npm install -g bats

# Or using package managers
# Ubuntu/Debian
sudo apt-get install bats

# macOS with Homebrew
brew install bats-core

# Or build from source
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local

# Test helper libraries (bats-support and bats-assert) are automatically
# set up as git submodules and will be cloned when you clone the repository
# with: git clone --recursive https://github.com/your-repo/suiteymk2.git
```

### Environment Setup
```bash
# Ensure Docker daemon is running
sudo systemctl start docker  # Linux
# or
open /Applications/Docker.app # macOS

# Set test environment variables (optional)
export SUITEY_TEST_MODE=true          # Enable test mode optimizations
export SUITEY_INTEGRATION_TEST=true   # Run integration tests
export DOCKER_TEST_TIMEOUT=300        # Docker operation timeout in seconds
```

## Running Tests

### Quick Start
```bash
# Run all tests
bats tests/bats/

# Run unit tests only
bats tests/bats/unit/

# Run integration tests only
bats tests/bats/integration/

# Run specific test file
bats tests/bats/unit/mod_registry.bats

# Run specific test
bats tests/bats/unit/mod_registry.bats -f "module registry initialization"
```

### Parallel Execution
```bash
# Run tests in parallel (recommended for faster execution)
bats -j 4 tests/bats/unit/        # 4 parallel jobs
bats -j $(nproc) tests/bats/unit/ # Use all CPU cores

# Parallel integration tests (be careful with Docker resource usage)
bats -j 2 tests/bats/integration/
```

### Test Filtering
```bash
# Run tests matching pattern
bats tests/bats/unit/ -f "module"

# Run tests with specific tags
bats tests/bats/unit/ --filter-tags "slow"

# Skip tests with specific tags
bats tests/bats/unit/ --filter-tags "!integration"
```

### Verbose Output
```bash
# Show detailed test output
bats -t tests/bats/unit/mod_registry.bats

# Show timing information
bats -T tests/bats/unit/

# Show TAP output (Test Anything Protocol)
bats --tap tests/bats/unit/
```

### Test Debugging
```bash
# Run with bash debugging
BATS_DEBUG=true bats tests/bats/unit/mod_registry.bats

# Run specific test with verbose output
bats -t tests/bats/unit/mod_registry.bats -f "test name"
```

## Test Guidelines for Parallel Execution

### Thread Safety
- **Isolation**: Each test must be completely isolated from others
- **No Shared State**: Tests cannot rely on or modify shared state
- **Resource Cleanup**: Tests must clean up all resources they create
- **Idempotent Operations**: Test operations should be idempotent

### Resource Management
```bash
# Good: Unique resource names
container_name="test_container_$$_$RANDOM"

# Bad: Shared resource names
container_name="test_container"
```

### Docker Resource Management
```bash
# Good: Parallel-safe Docker operations
docker run --name "test_$$_$RANDOM" --rm busybox echo "test"

# Bad: Potential conflicts
docker run --name "shared_container" busybox echo "test"
```

### File System Isolation
```bash
# Good: Unique temporary directories
test_dir="/tmp/test_$$_$RANDOM"
mkdir -p "$test_dir"

# Bad: Shared directories
test_dir="/tmp/shared_test_dir"
```

### Suitey Filesystem Principle Compliance

All tests must comply with Suitey's core principle of not modifying the host filesystem except for `/tmp`:

```bash
# Good: Use /tmp for all test artifacts
test_output="/tmp/suitey_test_output_$$_$RANDOM"
echo "test data" > "$test_output"

# Bad: Writing to project directory or other host locations
echo "test data" > "test_output.txt"
```

## Coding Patterns for Testability

### Test Structure Pattern
```bash
@test "component feature works correctly" {
    # Arrange
    setup_test_data

    # Act
    result=$(component_function "input")

    # Assert
    [ "$result" = "expected_output" ]
}
```

### Setup/Teardown Pattern
```bash
setup() {
    # Run before each test
    export TEST_TMP_DIR="/tmp/test_$$_$RANDOM"
    mkdir -p "$TEST_TMP_DIR"
}

teardown() {
    # Run after each test
    rm -rf "$TEST_TMP_DIR"
    cleanup_docker_containers
}
```

### Mock Usage Pattern
```bash
@test "function handles network failure" {
    # Mock network failure
    mock_command "curl" "exit 1"

    # Test error handling
    run component_function
    [ "$status" -eq 1 ]
    [ "$output" = "Network error occurred" ]
}
```

### Data-Driven Tests Pattern
```bash
test_cases=(
    "input1:expected1"
    "input2:expected2"
    "input3:expected3"
)

for test_case in "${test_cases[@]}"; do
    IFS=':' read -r input expected <<< "$test_case"
    @test "function handles $input correctly" {
        result=$(process_input "$input")
        [ "$result" = "$expected" ]
    }
done
```

## Mock System for Unit Tests

### Mock Architecture
```bash
# Mock system components
├── mock_registry/          # Stores mocked commands
├── mock_functions/         # Mock implementations
├── mock_data/             # Mock data files
└── mock_cleanup/          # Cleanup utilities
```

### Basic Mock Usage
```bash
# Mock a command to return specific output
mock_command "docker" "echo 'mocked docker output'"

# Mock a command to exit with specific code
mock_command "curl" "exit 1"

# Mock a function
mock_function "external_api_call" "echo 'mocked response'"

# Use in test
run my_function
[ "$output" = "mocked response" ]
```

### Advanced Mock Features
```bash
# Conditional mocking based on arguments
mock_command_conditional "docker" \
    "run" "echo 'run command mocked'" \
    "ps" "echo 'ps command mocked'"

# Mock with file output
mock_command_file "curl" "/path/to/mock/response.json"

# Sequence mocking (different responses for consecutive calls)
mock_command_sequence "unstable_api" \
    "echo 'first response'" \
    "exit 1" \
    "echo 'third response'"
```

### Docker Mocking
```bash
# Mock Docker operations for unit tests
mock_docker_build "myimage" "echo 'Build successful'"
mock_docker_run "mycontainer" "echo 'Container output'"
mock_docker_ps "" "echo 'container1
container2'"

# Test build manager without real Docker
run build_manager_execute
[ "$status" -eq 0 ]
```

### File System Mocking
```bash
# Mock file system operations
mock_file_exists "/path/to/file" true
mock_file_read "/path/to/file" "file contents"
mock_directory_list "/path" "file1
file2
dir1"

# Test file operations
run process_file "/path/to/file"
[ "$output" = "processed: file contents" ]
```

## Integration Tests

### Docker Integration Tests
```bash
# Test with real Docker operations
@test "build manager creates test image" {
    # Setup
    create_test_project

    # Execute build
    run build_manager_create_test_image \
        "$PROJECT_DIR" \
        "rust" \
        "$ARTIFACTS_DIR" \
        "test-image"

    # Verify
    [ "$status" -eq 0 ]
    docker image inspect "test-image" > /dev/null
}
```

### End-to-End Integration Tests
```bash
@test "complete test execution workflow" {
    # Setup multi-framework project
    create_rust_project
    create_bats_project

    # Run suitey
    run suitey "$PROJECT_DIR"

    # Verify results
    [ "$status" -eq 0 ]
    [ -f "/tmp/suitey-reports/report-*.html" ]
    grep -q "rust.*passed" "/tmp/suitey-reports/report-*.html"
    grep -q "bats.*passed" "/tmp/suitey-reports/report-*.html"
}
```

### Performance Integration Tests
```bash
@test "parallel execution performance" {
    # Setup large test suite
    create_large_test_suite 100

    # Measure execution time
    start_time=$(date +%s)
    run suitey "$PROJECT_DIR"
    end_time=$(date +%s)

    # Verify performance requirements
    duration=$((end_time - start_time))
    [ "$duration" -lt 300 ]  # Less than 5 minutes
}
```

## Best Practices

### Test Organization
- **One Concept Per Test**: Each test should verify one specific behavior
- **Descriptive Names**: Test names should clearly describe what they verify
- **Logical Grouping**: Group related tests in the same file
- **Independent Tests**: Tests should not depend on each other

### Mock Best Practices
- **Minimal Mocking**: Mock only external dependencies, not internal functions
- **Realistic Mocks**: Mocks should behave like real implementations
- **Complete Setup**: Set up all necessary mocks before test execution
- **Clean Teardown**: Unmock all mocked functions after test completion

### Assertion Best Practices
- **Clear Assertions**: Use descriptive assertion messages
- **Multiple Assertions**: Test multiple aspects of the same operation
- **Negative Testing**: Test both success and failure scenarios
- **Edge Cases**: Include tests for edge cases and error conditions

### Performance Best Practices
- **Fast Tests**: Keep individual tests under 1 second
- **Resource Aware**: Be mindful of system resource usage
- **Parallel Friendly**: Design tests to run safely in parallel
- **Cleanup**: Always clean up resources after tests

## Troubleshooting

### Common Test Failures

#### Docker-Related Issues
```bash
# Check Docker daemon status
docker info

# Verify Docker is accessible
docker run --rm hello-world

# Check Docker resource usage
docker system df
```

#### Permission Issues
```bash
# Fix Docker permissions (Linux)
sudo usermod -aG docker $USER
newgrp docker

# Check file permissions
ls -la /tmp/suitey-*
```

#### Resource Exhaustion
```bash
# Clean up Docker resources
docker system prune -f
docker volume prune -f

# Check system resources
df -h
free -h
```

### Test Debugging Techniques

#### Verbose Test Output
```bash
# Enable verbose mode
export BATS_VERBOSE_RUN=1

# Run with tracing
bash -x "$(which bats)" tests/bats/unit/test.bats
```

#### Test Isolation Debugging
```bash
# Run single test in isolation
bats tests/bats/unit/test.bats -f "specific test name"

# Check for test interference
bats tests/bats/unit/test.bats -f "test1"
bats tests/bats/unit/test.bats -f "test2"
```

#### Mock Debugging
```bash
# Verify mocks are active
mock_status

# Check mock call counts
mock_call_count "command_name"

# Inspect mock responses
mock_inspect "command_name"
```

### Flaky Test Debugging
```bash
# Run test multiple times
for i in {1..10}; do
    echo "Run $i:"
    bats tests/bats/unit/test.bats -f "flaky test" || break
done

# Add timing information
BATS_TIMING=1 bats tests/bats/unit/test.bats
```

## CI/CD Integration

### GitHub Actions Example
```yaml
name: Suitey Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    - name: Setup Docker
      run: |
        sudo systemctl start docker
        docker version
    - name: Install BATS
      run: npm install -g bats bats-support bats-assert
    - name: Run Unit Tests
      run: bats -j 4 tests/bats/unit/
    - name: Run Integration Tests
      run: bats -j 2 tests/bats/integration/
```

### Jenkins Pipeline Example
```groovy
pipeline {
    agent any
    stages {
        stage('Setup') {
            steps {
                sh 'sudo systemctl start docker'
                sh 'npm install -g bats bats-support bats-assert'
            }
        }
        stage('Unit Tests') {
            steps {
                sh 'bats -j 4 tests/bats/unit/'
            }
        }
        stage('Integration Tests') {
            steps {
                sh 'bats -j 2 tests/bats/integration/'
            }
        }
    }
}
```

### CircleCI Example
```yaml
version: 2.1
jobs:
  test:
    docker:
      - image: cimg/base:2021.04
    steps:
      - checkout
      - setup_remote_docker
      - run:
          name: Install Dependencies
          command: npm install -g bats bats-support bats-assert
      - run:
          name: Unit Tests
          command: bats -j 4 tests/bats/unit/
      - run:
          name: Integration Tests
          command: bats -j 2 tests/bats/integration/
```

### Test Reporting
```bash
# Generate test reports
bats --tap tests/bats/ > test_results.tap

# Convert to JUnit XML for CI systems
tap2junit test_results.tap > test_results.xml

# Generate coverage reports (if applicable)
# Custom coverage reporting scripts
```

### Performance Monitoring
```bash
# Measure test execution time
time bats tests/bats/

# Profile test performance
bats --timing tests/bats/ > timing.log

# Monitor resource usage
#!/bin/bash
bats tests/bats/ &
BATS_PID=$!
while kill -0 $BATS_PID 2>/dev/null; do
    ps -o pid,ppid,pcpu,pmem,cmd -C bats
    sleep 1
done
```

## Test Development Workflow

### Adding New Tests
```bash
# Create new test file
touch tests/bats/unit/new_component.bats

# Add basic structure
#!/usr/bin/env bats
load '../helpers/common_setup'

@test "new component basic functionality" {
    # Test implementation
}
```

### Test-Driven Development
```bash
# 1. Write failing test
@test "new feature works" {
    run new_feature "input"
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}

# 2. Run test to confirm failure
bats tests/bats/unit/new_feature.bats

# 3. Implement feature
# Edit source code to make test pass

# 4. Run test to confirm success
bats tests/bats/unit/new_feature.bats

# 5. Refactor and re-test
# Optimize implementation while keeping tests passing
```

### Test Maintenance
```bash
# Regular test maintenance tasks
- Review and update flaky tests
- Remove obsolete tests
- Add tests for new features
- Update tests for API changes
- Monitor test performance
- Fix broken tests promptly
```

## Advanced Testing Techniques

### Property-Based Testing
```bash
# Generate test inputs
generate_random_string() {
    local length=${1:-10}
    tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

@test "function handles various inputs" {
    for i in {1..100}; do
        input=$(generate_random_string)
        run process_input "$input"
        [ "$status" -eq 0 ]
    done
}
```

### Load Testing
```bash
@test "component handles high load" {
    # Create multiple concurrent operations
    for i in {1..10}; do
        process_input "input$i" &
    done

    # Wait for all operations
    wait

    # Verify results
    [ "$(count_results)" -eq 10 ]
}
```

### Chaos Testing
```bash
@test "component handles resource failures" {
    # Simulate network failures
    mock_command "curl" "exit 1"

    # Simulate disk full
    mock_command "df" "echo '/dev/sda1 100% used'"

    # Test resilience
    run resilient_function
    [ "$status" -eq 0 ]
}
```

This comprehensive testing approach ensures Suitey maintains high code quality, reliability, and performance across all components and integration points.
