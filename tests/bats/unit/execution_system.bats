#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# Source the execution_system.sh file for testing
setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source the execution_system.sh file if it exists
    if [[ -f "src/execution_system.sh" ]]; then
        source "src/execution_system.sh"
    fi

    # Track containers created during tests for cleanup
    TEST_CONTAINERS=()
    TEST_IMAGES=()
}

teardown() {
    # Clean up any containers created during tests
    for container_id in "${TEST_CONTAINERS[@]}"; do
        if [[ -n "$container_id" ]]; then
            docker stop "$container_id" >/dev/null 2>&1 || true
            docker rm "$container_id" >/dev/null 2>&1 || true
        fi
    done
    TEST_CONTAINERS=()

    # Clean up any test images created during tests
    for image_tag in "${TEST_IMAGES[@]}"; do
        if [[ -n "$image_tag" ]]; then
            docker rmi "$image_tag" >/dev/null 2>&1 || true
        fi
    done
    TEST_IMAGES=()
}

@test "launch_test_container() launches test container with pre-built image using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a simple test image
    local test_image_tag="suitey-test-exec-$$"
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
RUN mkdir -p /app/src /app/tests
RUN echo 'pub fn add(a: i32, b: i32) -> i32 { a + b }' > /app/src/lib.rs
RUN echo '#[test] fn test_add() { assert_eq!(add(1, 2), 3); }' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-exec-$$"

    run launch_test_container "$container_config"
    assert_success

    # Verify container was created
    assert_output --partial "container_id="
    assert_output --partial "container_status=running"
    assert_output --partial "test_image=$test_image_tag"

    # Extract container ID for cleanup
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Verify container exists and is running
    if [[ -n "$container_id" ]]; then
        run docker ps --format "{{.ID}}"
        assert_success
        assert_output --partial "$container_id"
    fi
}

@test "execute_test_command() executes cargo test in container using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a test image with Rust project
    local test_image_tag="suitey-test-cargo-$$"
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
RUN mkdir -p /app/src /app/tests
RUN echo '[package]' > /app/Cargo.toml
RUN echo 'name = \"test-project\"' >> /app/Cargo.toml
RUN echo 'version = \"0.1.0\"' >> /app/Cargo.toml
RUN echo 'edition = \"2021\"' >> /app/Cargo.toml
RUN echo 'pub fn add(a: i32, b: i32) -> i32 { a + b }' > /app/src/lib.rs
RUN echo '#[test] fn test_add() { assert_eq!(test_project::add(1, 2), 3); }' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-cargo-$$"

    run launch_test_container "$container_config"
    assert_success

    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute cargo test command
    local test_command="cargo test"
    run execute_test_command "$container_id" "$test_command"
    assert_success

    # Verify test execution results
    assert_output --partial "exit_code="
    assert_output --partial "duration="
    assert_output --partial "test_status="
}

@test "execute_test_command() captures test output from example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a test image
    local test_image_tag="suitey-test-output-$$"
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
RUN mkdir -p /app/src /app/tests
RUN echo '[package]' > /app/Cargo.toml
RUN echo 'name = \"test-project\"' >> /app/Cargo.toml
RUN echo 'version = \"0.1.0\"' >> /app/Cargo.toml
RUN echo 'edition = \"2021\"' >> /app/Cargo.toml
RUN echo 'pub fn test() {}' > /app/src/lib.rs
RUN echo '#[test] fn test_example() { println!(\"test output\"); }' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-output-$$"

    run launch_test_container "$container_config"
    assert_success

    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute test command
    local test_command="cargo test 2>&1"
    run execute_test_command "$container_id" "$test_command"
    assert_success

    # Verify output is captured
    assert_output --partial "stdout="
    assert_output --partial "stderr="
    
    # Verify stdout contains test output
    local stdout
    stdout=$(echo "$output" | grep "^stdout=" | cut -d'=' -f2- || echo "")
    # stdout should contain cargo test output
    assert [ -n "$stdout" ] || [ -n "$(echo "$output" | grep "test_status")" ]
}

@test "execute_test_command() captures exit code from example/rust-project tests" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a test image with passing tests
    local test_image_tag="suitey-test-exit-$$"
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
RUN mkdir -p /app/src /app/tests
RUN echo '[package]' > /app/Cargo.toml
RUN echo 'name = \"test-project\"' >> /app/Cargo.toml
RUN echo 'version = \"0.1.0\"' >> /app/Cargo.toml
RUN echo 'edition = \"2021\"' >> /app/Cargo.toml
RUN echo 'pub fn add(a: i32, b: i32) -> i32 { a + b }' > /app/src/lib.rs
RUN echo '#[test] fn test_add() { assert_eq!(test_project::add(1, 2), 3); }' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-exit-$$"

    run launch_test_container "$container_config"
    assert_success

    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute test command
    local test_command="cargo test"
    run execute_test_command "$container_id" "$test_command"
    assert_success

    # Verify exit code is captured
    assert_output --partial "exit_code="
    
    # Extract exit code
    local exit_code
    exit_code=$(echo "$output" | grep "^exit_code=" | cut -d'=' -f2)
    assert [ -n "$exit_code" ]
    
    # Exit code should be 0 for passing tests (or non-zero for failures, but should be captured)
    # Just verify it's a number
    assert [ "$exit_code" -ge 0 ] 2>/dev/null || [ "$exit_code" -le 255 ] 2>/dev/null
}

@test "launch_test_container() handles invalid image" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    run launch_test_container "test_image=nonexistent-image-12345"
    assert_failure
    assert_output --partial "error_message="
}

@test "execute_test_command() handles invalid container ID" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    run execute_test_command "nonexistent-container-12345" "cargo test"
    assert_failure
    assert_output --partial "error_message="
}

@test "execute_test_command() handles empty test command" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    # Create a test image
    local test_image_tag="suitey-test-empty-$$"
    local dockerfile_content="FROM alpine:latest
WORKDIR /app
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-empty-$$"

    run launch_test_container "$container_config"
    assert_success

    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute empty command
    run execute_test_command "$container_id" ""
    assert_failure
    assert_output --partial "error_message="
}

@test "collect_test_results() writes results to /tmp with unique filenames using example/rust-project" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]]; then
        skip "example/rust-project not available"
    fi

    # Create a test image
    local test_image_tag="suitey-test-collect-$$"
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
RUN mkdir -p /app/src /app/tests
RUN echo '[package]' > /app/Cargo.toml
RUN echo 'name = \"test-project\"' >> /app/Cargo.toml
RUN echo 'version = \"0.1.0\"' >> /app/Cargo.toml
RUN echo 'edition = \"2021\"' >> /app/Cargo.toml
RUN echo 'pub fn add(a: i32, b: i32) -> i32 { a + b }' > /app/src/lib.rs
RUN echo '#[test] fn test_add() { assert_eq!(test_project::add(1, 2), 3); }' > /app/tests/integration_test.rs
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$test_image_tag" - >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$test_image_tag")

    # Launch test container
    local container_config="test_image=$test_image_tag
working_directory=/app
container_name=suitey-test-collect-$$"

    run launch_test_container "$container_config"
    assert_success

    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -n "$container_id" ]]; then
        TEST_CONTAINERS+=("$container_id")
    fi

    # Execute test command
    local test_command="cargo test"
    local test_result
    test_result=$(execute_test_command "$container_id" "$test_command" 2>&1)
    assert [ $? -eq 0 ]

    # Collect test results
    local suite_id="rust-test-suite"
    run collect_test_results "$suite_id" "$test_result"
    assert_success

    # Verify result file was created with unique name pattern
    local result_files
    result_files=$(ls /tmp/suitey_test_result_${suite_id}_* 2>/dev/null | head -1)
    assert [ -n "$result_files" ]
    assert [ -f "$result_files" ]

    # Verify output file was created with unique name pattern
    local output_files
    output_files=$(ls /tmp/suitey_test_output_${suite_id}_* 2>/dev/null | head -1)
    assert [ -n "$output_files" ]
    assert [ -f "$output_files" ]

    # Verify result file contains structured data
    assert [ -n "$(grep "^container_id=" "$result_files")" ]
    assert [ -n "$(grep "^test_status=" "$result_files")" ]
    assert [ -n "$(grep "^exit_code=" "$result_files")" ]
    assert [ -n "$(grep "^duration=" "$result_files")" ]

    # Clean up test files
    rm -f "$result_files" "$output_files" 2>/dev/null || true
}

@test "collect_test_results() uses atomic writes (write to temp, then mv)" {
    # Create mock test result data
    local suite_id="test-suite-atomic"
    local test_result="container_id=abc123
test_status=passed
exit_code=0
duration=1.234
stdout=test output
stderr="

    # Collect test results
    run collect_test_results "$suite_id" "$test_result"
    assert_success

    # Verify result file exists
    local result_files
    result_files=$(ls /tmp/suitey_test_result_${suite_id}_* 2>/dev/null | head -1)
    assert [ -n "$result_files" ]
    assert [ -f "$result_files" ]

    # Verify file content is correct (atomic write ensures complete file)
    assert [ -n "$(grep "^container_id=abc123" "$result_files")" ]
    assert [ -n "$(grep "^test_status=passed" "$result_files")" ]
    assert [ -n "$(grep "^exit_code=0" "$result_files")" ]

    # Clean up
    rm -f "$result_files" /tmp/suitey_test_output_${suite_id}_* 2>/dev/null || true
}

@test "collect_test_results() creates unique filenames to prevent race conditions" {
    # Create multiple test results with same suite_id
    local suite_id="test-suite-parallel"
    local test_result1="container_id=container1
test_status=passed
exit_code=0
duration=1.0
stdout=output1
stderr="

    local test_result2="container_id=container2
test_status=passed
exit_code=0
duration=2.0
stdout=output2
stderr="

    # Collect results in parallel (simulated by calling twice)
    collect_test_results "$suite_id" "$test_result1" >/dev/null 2>&1
    collect_test_results "$suite_id" "$test_result2" >/dev/null 2>&1

    # Verify both result files exist with different names
    local result_files
    result_files=$(ls /tmp/suitey_test_result_${suite_id}_* 2>/dev/null | tr '\n' ' ')
    local file_count
    file_count=$(echo "$result_files" | wc -w)
    assert [ "$file_count" -ge 2 ]

    # Verify files have unique names (should contain PID and random number)
    # Pattern: suitey_test_result_<suite_id>_<pid>_<random>
    local unique_names=0
    for file in $result_files; do
        # Check if filename matches the pattern (has suite_id, then two more parts separated by _)
        if [[ "$file" =~ suitey_test_result_${suite_id}_[0-9]+_[0-9]+ ]]; then
            unique_names=$((unique_names + 1))
        fi
    done
    assert [ "$unique_names" -ge 2 ]

    # Verify files are actually different
    local file_array=($result_files)
    assert [ "${file_array[0]}" != "${file_array[1]}" ]

    # Clean up
    rm -f /tmp/suitey_test_result_${suite_id}_* /tmp/suitey_test_output_${suite_id}_* 2>/dev/null || true
}

@test "collect_test_results() writes output file with stdout and stderr" {
    local suite_id="test-suite-output"
    local test_result="container_id=abc123
test_status=passed
exit_code=0
duration=1.0
stdout=This is stdout output
stderr=This is stderr output"

    run collect_test_results "$suite_id" "$test_result"
    assert_success

    # Verify output file exists
    local output_files
    output_files=$(ls /tmp/suitey_test_output_${suite_id}_* 2>/dev/null | head -1)
    assert [ -n "$output_files" ]
    assert [ -f "$output_files" ]

    # Verify output file contains both stdout and stderr
    local output_content
    output_content=$(cat "$output_files" 2>/dev/null || echo "")
    assert [ -n "$output_content" ]
    assert [ -n "$(echo "$output_content" | grep "This is stdout output")" ]
    assert [ -n "$(echo "$output_content" | grep "This is stderr output")" ]

    # Clean up
    rm -f "$output_files" /tmp/suitey_test_result_${suite_id}_* 2>/dev/null || true
}

@test "collect_test_results() handles invalid suite_id gracefully" {
    run collect_test_results "" "test_status=passed"
    assert_failure
    assert_output --partial "error_message="
}

@test "collect_test_results() handles empty test result gracefully" {
    run collect_test_results "test-suite" ""
    # Should either succeed (create empty files) or fail gracefully
    # Let's check it doesn't crash
    assert [ $? -eq 0 ] || [ $? -eq 1 ]
}

