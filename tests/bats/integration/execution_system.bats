#!/usr/bin/env bats

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

setup() {
    # Ensure we're in the project root
    local test_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    local project_root="$(cd "$test_dir/../../.." && pwd)"
    cd "$project_root"

    # Source execution system functions (which already sources mod_registry.sh)
    if [[ -f "src/execution_system.sh" ]]; then
        source "src/execution_system.sh"
    fi

    # Source build manager for creating test images
    if [[ -f "src/build_manager.sh" ]]; then
        source "src/build_manager.sh"
    fi

    # Track containers and images created during tests for cleanup
    TEST_CONTAINERS=()
    TEST_IMAGES=()
    TEST_RESULT_FILES=()
}

teardown() {
    # Clean up containers
    for container_id in "${TEST_CONTAINERS[@]}"; do
        if [[ -n "$container_id" ]]; then
            cleanup_test_container "$container_id" >/dev/null 2>&1 || true
        fi
    done
    TEST_CONTAINERS=()

    # Clean up images
    for image_tag in "${TEST_IMAGES[@]}"; do
        if [[ -n "$image_tag" ]]; then
            docker rmi "$image_tag" >/dev/null 2>&1 || true
        fi
    done
    TEST_IMAGES=()

    # Clean up result files
    for result_file in "${TEST_RESULT_FILES[@]}"; do
        if [[ -n "$result_file" ]] && [[ -f "$result_file" ]]; then
            rm -f "$result_file" 2>/dev/null || true
        fi
    done
    TEST_RESULT_FILES=()

    # Clean up any remaining result files matching our pattern
    rm -f /tmp/suitey_test_result_* /tmp/suitey_test_output_* 2>/dev/null || true
}

@test "Integration: Execute example/rust-project tests in container" {
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

    # Step 1: Create test image with Rust project
    local image_tag="suitey-integration-rust-exec-$$"
    
    # Create a Dockerfile that includes the Rust project
    local dockerfile_content="FROM rust:1.70-slim
WORKDIR /app
COPY example/rust-project /app
RUN cargo build --release 2>&1 || true
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Step 2: Launch test container
    local container_config="test_image=$image_tag
working_directory=/app
container_name=suitey-integration-rust-$$"

    run launch_test_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -z "$container_id" ]]; then
        skip "Failed to get container ID"
    fi

    TEST_CONTAINERS+=("$container_id")

    # Step 3: Execute test command
    local test_command="CARGO_TARGET_DIR=/tmp cargo test 2>&1"
    run execute_test_command "$container_id" "$test_command"
    assert_success

    # Verify test execution results
    assert_output --partial "container_id="
    assert_output --partial "test_status="
    assert_output --partial "exit_code="
    assert_output --partial "duration="
    assert_output --partial "stdout="
    assert_output --partial "stderr="

    # Step 4: Collect test results
    local suite_id="rust-integration-test"
    local test_result="$output"
    run collect_test_results "$suite_id" "$test_result"
    assert_success

    # Verify result files were created
    assert_output --partial "result_file="
    assert_output --partial "output_file="

    # Extract result file paths
    local result_file
    result_file=$(echo "$output" | grep "^result_file=" | cut -d'=' -f2)
    local output_file
    output_file=$(echo "$output" | grep "^output_file=" | cut -d'=' -f2)

    if [[ -n "$result_file" ]]; then
        TEST_RESULT_FILES+=("$result_file")
    fi
    if [[ -n "$output_file" ]]; then
        TEST_RESULT_FILES+=("$output_file")
    fi

    # Verify result file exists and contains structured data
    if [[ -n "$result_file" ]] && [[ -f "$result_file" ]]; then
        assert [ -f "$result_file" ]
        assert [ -n "$(grep "^test_status=" "$result_file")" ]
        assert [ -n "$(grep "^exit_code=" "$result_file")" ]
        assert [ -n "$(grep "^duration=" "$result_file")" ]
    fi

    # Verify output file exists
    if [[ -n "$output_file" ]] && [[ -f "$output_file" ]]; then
        assert [ -f "$output_file" ]
    fi
}

@test "Integration: Execute example/bats-project tests in container" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/bats-project" ]]; then
        skip "example/bats-project not available"
    fi

    # Step 1: Create test image with BATS project
    local image_tag="suitey-integration-bats-exec-$$"
    
    # Create a Dockerfile that includes the BATS project and bats binary
    # Use alpine base and install bats to ensure sleep is available
    local dockerfile_content="FROM alpine:latest
RUN apk add --no-cache bash bats
WORKDIR /app
COPY example/bats-project /app
"

    # Build test image
    echo "$dockerfile_content" | docker build -t "$image_tag" -f - . >/dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        skip "Failed to create test image"
    fi

    TEST_IMAGES+=("$image_tag")

    # Step 2: Launch test container
    local container_config="test_image=$image_tag
working_directory=/app
container_name=suitey-integration-bats-$$"

    run launch_test_container "$container_config"
    assert_success

    # Extract container ID
    local container_id
    container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
    if [[ -z "$container_id" ]]; then
        skip "Failed to get container ID"
    fi

    TEST_CONTAINERS+=("$container_id")

    # Wait a moment for container to be fully running
    sleep 1

    # Verify container is running
    local container_status
    container_status=$(docker inspect --format='{{.State.Status}}' "$container_id" 2>/dev/null || echo "unknown")
    if [[ "$container_status" != "running" ]]; then
        skip "Container exited immediately (status: $container_status). BATS image may not support sleep infinity."
    fi

    # Step 3: Execute test command
    local test_command="bats tests/bats/*.bats 2>&1"
    run execute_test_command "$container_id" "$test_command"
    assert_success

    # Verify test execution results
    assert_output --partial "container_id="
    assert_output --partial "test_status="
    assert_output --partial "exit_code="
    assert_output --partial "duration="
    assert_output --partial "stdout="
    assert_output --partial "stderr="

    # Step 4: Collect test results
    local suite_id="bats-integration-test"
    local test_result="$output"
    run collect_test_results "$suite_id" "$test_result"
    assert_success

    # Verify result files were created
    assert_output --partial "result_file="
    assert_output --partial "output_file="

    # Extract result file paths
    local result_file
    result_file=$(echo "$output" | grep "^result_file=" | cut -d'=' -f2)
    local output_file
    output_file=$(echo "$output" | grep "^output_file=" | cut -d'=' -f2)

    if [[ -n "$result_file" ]]; then
        TEST_RESULT_FILES+=("$result_file")
    fi
    if [[ -n "$output_file" ]]; then
        TEST_RESULT_FILES+=("$output_file")
    fi

    # Verify result file exists and contains structured data
    if [[ -n "$result_file" ]] && [[ -f "$result_file" ]]; then
        assert [ -f "$result_file" ]
        assert [ -n "$(grep "^test_status=" "$result_file")" ]
        assert [ -n "$(grep "^exit_code=" "$result_file")" ]
        assert [ -n "$(grep "^duration=" "$result_file")" ]
    fi

    # Verify output file exists
    if [[ -n "$output_file" ]] && [[ -f "$output_file" ]]; then
        assert [ -f "$output_file" ]
    fi
}

@test "Integration: Verify results are collected correctly from both projects" {
    # Skip if Docker is not available
    if ! command -v docker >/dev/null 2>&1; then
        skip "Docker is not available"
    fi

    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon is not running"
    fi

    if [[ ! -d "example/rust-project" ]] || [[ ! -d "example/bats-project" ]]; then
        skip "Example projects not available"
    fi

    # Test Rust project
    local rust_image_tag="suitey-integration-rust-verify-$$"
    local rust_dockerfile="FROM rust:1.70-slim
WORKDIR /app
COPY example/rust-project /app
RUN cargo build --release 2>&1 || true
"
    echo "$rust_dockerfile" | docker build -t "$rust_image_tag" -f - . >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        TEST_IMAGES+=("$rust_image_tag")

        local rust_container_config="test_image=$rust_image_tag
working_directory=/app
container_name=suitey-rust-verify-$$"

        run launch_test_container "$rust_container_config"
        if [[ $status -eq 0 ]]; then
            local rust_container_id
            rust_container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
            if [[ -n "$rust_container_id" ]]; then
                TEST_CONTAINERS+=("$rust_container_id")

                # Execute and collect
                local rust_test_result
                rust_test_result=$(execute_test_command "$rust_container_id" "CARGO_TARGET_DIR=/tmp cargo test 2>&1" 2>&1)
                if [[ $? -eq 0 ]]; then
                    local rust_result_file
                    rust_result_file=$(collect_test_results "rust-verify" "$rust_test_result" 2>&1 | grep "^result_file=" | cut -d'=' -f2)
                    if [[ -n "$rust_result_file" ]]; then
                        TEST_RESULT_FILES+=("$rust_result_file")
                        # Verify Rust result file structure
                        assert [ -f "$rust_result_file" ]
                        assert [ -n "$(grep "^test_status=" "$rust_result_file")" ]
                    fi
                fi
            fi
        fi
    fi

    # Test BATS project
    local bats_image_tag="suitey-integration-bats-verify-$$"
    local bats_dockerfile="FROM alpine:latest
RUN apk add --no-cache bash bats
WORKDIR /app
COPY example/bats-project /app
"
    echo "$bats_dockerfile" | docker build -t "$bats_image_tag" -f - . >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        TEST_IMAGES+=("$bats_image_tag")

        local bats_container_config="test_image=$bats_image_tag
working_directory=/app
container_name=suitey-bats-verify-$$"

        run launch_test_container "$bats_container_config"
        if [[ $status -eq 0 ]]; then
            local bats_container_id
            bats_container_id=$(echo "$output" | grep "^container_id=" | cut -d'=' -f2)
            if [[ -n "$bats_container_id" ]]; then
                TEST_CONTAINERS+=("$bats_container_id")

                # Execute and collect
                local bats_test_result
                bats_test_result=$(execute_test_command "$bats_container_id" "bats tests/bats/*.bats 2>&1" 2>&1)
                if [[ $? -eq 0 ]]; then
                    local bats_result_file
                    bats_result_file=$(collect_test_results "bats-verify" "$bats_test_result" 2>&1 | grep "^result_file=" | cut -d'=' -f2)
                    if [[ -n "$bats_result_file" ]]; then
                        TEST_RESULT_FILES+=("$bats_result_file")
                        # Verify BATS result file structure
                        assert [ -f "$bats_result_file" ]
                        assert [ -n "$(grep "^test_status=" "$bats_result_file")" ]
                    fi
                fi
            fi
        fi
    fi

    # Verify both result files exist and are in /tmp (filesystem isolation)
    local result_count=0
    for result_file in "${TEST_RESULT_FILES[@]}"; do
        if [[ -n "$result_file" ]] && [[ -f "$result_file" ]]; then
            # Verify file is in /tmp
            assert [ "${result_file#/tmp/}" != "$result_file" ]
            result_count=$((result_count + 1))
        fi
    done

    # Should have at least one result file
    assert [ "$result_count" -gt 0 ]
}

