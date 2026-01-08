# Build Manager Specification

## Overview

The Build Manager is a core component of Suitey responsible for orchestrating the execution of build steps required before test execution. It operates after Build System Detection has identified which frameworks require building, and coordinates the containerized execution of build steps across multiple frameworks, managing build artifacts, and ensuring builds complete successfully before test execution begins.

The Build Manager ensures that:
- Build steps execute in isolated, containerized environments
- Build containers utilize multiple CPU cores when available for faster builds
- Dependencies are installed in build containers before building
- Build artifacts are preserved and packaged into Docker images for test containers
- Test images contain build artifacts, source code, and test suites (self-contained)
- Independent builds run in parallel for efficiency
- Build failures are detected and reported clearly
- Build status is tracked and reported in real-time
- All build operations respect Suitey's principle of not modifying the host filesystem except for `/tmp`

## Responsibilities

The Build Manager is responsible for:

1. **Build Orchestration**: Coordinating the execution of build steps for all frameworks that require building
2. **Container Management**: Launching, monitoring, and cleaning up Docker containers for builds
3. **Multi-Core Build Support**: Allocating multiple CPU cores to build containers when available
4. **Dependency Installation**: Installing dependencies in build containers before building
5. **Artifact Management**: Extracting build artifacts and packaging them into Docker images
6. **Test Image Creation**: Creating Docker images containing build artifacts, source code, and test suites
7. **Dockerfile Generation**: Generating Dockerfiles for test containers
8. **Parallel Execution**: Running independent builds in parallel when possible
9. **Status Tracking**: Tracking build progress and status for real-time reporting
10. **Error Handling**: Detecting build failures and providing clear error messages
11. **Signal Handling**: Responding to interruption signals (SIGINT) during build execution
12. **Filesystem Isolation**: Ensuring all build operations only use `/tmp` for temporary files and artifacts
13. **Integration**: Working with Project Scanner to receive build requirements and coordinate with test execution

## Architecture Position

The Build Manager is a component within the main suitey process:

```
┌─────────────────────────────────────┐
│         suitey (main process)       │
├─────────────────────────────────────┤
│  Project Scanner (Orchestrator)     │
│  ├─ Platform Detector               │
│  ├─ Test Suite Detector              │
│  └─ Build System Detector           │
│  Build Manager  ←───────────────────┤ (this component)
│  Parallel Execution Manager         │
├─────────────────────────────────────┤
│  Shared Components:                 │
│  • Suitey Modules Registry          │
│  • Result Storage (structured data) │
└─────────────────────────────────────┘
```

## Interface

### Input

The Build Manager receives build requirements from Project Scanner:

- **Build Requirements**: A collection of build specifications, one per framework that requires building
  - Framework identifier
  - Build steps (commands, Docker image, etc.)
  - Build dependencies (if any)
  - Artifact storage requirements
  - Suitey Module reference (for build step execution)

### Output

The Build Manager provides:

- **Build Results**: Structured data for each build attempt
  - Build status: `building`, `built`, `build-failed`
  - Build duration
  - Build output (stdout/stderr)
  - Error messages (if build failed)
  - Container IDs (for tracking and cleanup)

- **Test Image Metadata**: Information about created test images
  - Test image name/tag
  - Image ID
  - Dockerfile location
  - Framework associations
  - Artifact locations within image

## Workflow

### 1. Initialization

- Receive build requirements from Project Scanner
- Validate that Docker is available and accessible
- Create temporary directory structure in `/tmp` for build artifacts (if needed)
- Initialize build tracking structures
- Determine build dependencies and execution order

### 2. Build Dependency Analysis

- Analyze build requirements to identify dependencies between builds
- Group builds into dependency tiers:
  - **Tier 0**: Builds with no dependencies (can run immediately in parallel)
  - **Tier 1**: Builds that depend on Tier 0 builds
  - **Tier N**: Builds that depend on Tier N-1 builds
- Identify independent builds that can run in parallel
- Determine sequential execution requirements for dependent builds

### 3. Build Execution

For each dependency tier (executed sequentially):

1. **Parallel Launch**: Launch all builds in the current tier in parallel
   - For each build:
     - Determine build execution method from Suitey Module:
       - Docker container with build command
       - Custom build script execution
     - Create temporary directory in `/tmp` for build artifacts (for extraction)
     - Launch build container with appropriate configuration:
       - Use base image specified by Suitey Module (e.g., `rust:latest`)
       - Mount project directory (read-only) - project filesystem is never modified
       - Mount artifact volume from `/tmp` (read-write) for build outputs (temporary, for extraction)
       - Set working directory
       - Configure environment variables
       - Allocate multiple CPU cores when available (via `--cpus` or `--cpu-shares`)
       - Execute dependency installation commands (if specified by module)
       - Execute build command(s) from Suitey Module with multi-core support
     - Track container ID for monitoring and cleanup
     - Record start time

2. **Build Monitoring**: Monitor all running builds
   - Poll container status
   - Capture stdout/stderr output
   - Track build progress
   - Update build status in real-time
   - Report status to dashboard/verbose formatters

3. **Build Completion**: Wait for all builds in tier to complete
   - Capture exit codes
   - Calculate build duration
   - Extract build artifacts from containers to temporary location
   - Record build results

4. **Failure Detection**: Check for build failures
   - If any build fails:
     - Abort remaining builds in current tier (if applicable)
     - Collect error output from failed builds
     - Clean up build containers
     - Report build failures with clear error messages
     - Return failure status to Project Scanner (prevents test execution)

### 4. Test Image Creation

For each successful build:

1. **Artifact Extraction**: Extract build artifacts from build container
   - Copy artifacts from container to temporary staging directory
   - Verify artifact integrity
   - Organize artifacts by type and location

2. **Dockerfile Generation**: Create Dockerfile for test image
   - Base image: Use same base image as build (or Suitey Module specifies test base)
   - Copy build artifacts to appropriate locations in image
   - Copy source code to image
   - Copy test suites to image
   - Set working directory
   - Configure environment variables
   - Install test dependencies (if needed)
   - Set entrypoint/command for test execution (if applicable)

3. **Image Building**: Build Docker image from generated Dockerfile
   - Use `docker build` with appropriate context
   - Tag image with framework identifier and timestamp (e.g., `suitey-test-rust-20240115-143045`)
   - Track image ID for cleanup
   - Verify image build success

5. **Image Verification**: Verify test image is ready
   - Check image exists and is accessible
   - Verify artifacts are present in image
   - Verify source code is present
   - Verify test suites are present

### 5. Artifact Preparation

- Link test images to their corresponding test suites
- Provide test image metadata to test execution system
- Verify all test images are ready before test execution begins

### 6. Cleanup

- Remove build containers (after artifacts are extracted)
- Remove temporary artifact volumes (artifacts are now in test images)
- Clean up temporary build files and staging directories
- Track containers and images for signal-based cleanup
- Test images are preserved for test execution (cleaned up after tests complete)

## Build Detection Integration

The Build Manager works with Build System Detector (via Project Scanner) and Suitey Modules:

1. **Build Requirements**: Project Scanner uses Suitey Modules to determine build requirements per language
   - Each module implements `detect_build_requirements()` method
   - Modules check for build configuration files, source patterns, etc.
   - Modules specify build commands and execution methods

2. **Build Steps**: Suitey Modules provide build execution specifications:
   - Build commands (e.g., `cargo build`, `make`)
   - Docker image requirements
   - Environment variables
   - Volume mount requirements
   - Build dependencies

3. **Build Execution**: Build Manager uses module's `get_build_steps()` method to:
   - Determine execution method (Docker container, etc.)
   - Get build commands
   - Configure container environment
   - Execute builds in isolated containers

## Containerized Execution

### Docker Container Execution

Builds execute in Docker containers to ensure:
- **Consistent Environments**: Same build environment across platforms
- **Dependency Isolation**: Build dependencies don't conflict with host system
- **Reproducibility**: Builds are reproducible across different machines
- **Artifact Isolation**: Build artifacts are contained and managed

### Container Configuration

Each build container is configured with:

- **Base Image**: Determined by Suitey Module (e.g., `rust:latest`)
- **CPU Allocation**: Multiple CPU cores allocated when available (via `--cpus` or `--cpu-shares`)
- **Working Directory**: Project root or framework-specific build directory
- **Volume Mounts**:
  - Project directory (read-only) - project filesystem is never modified
  - Artifact volume from `/tmp` (read-write) for build outputs (temporary, for extraction)
  - Temporary directory in `/tmp` for intermediate files
- **Environment Variables**: Framework-specific variables (e.g., `CARGO_TARGET_DIR`)
- **Build Commands**:
  1. Dependency installation commands (if specified by module)
  2. Build commands with multi-core support (e.g., `make -j$(nproc)`, `cargo build --jobs $(nproc)`)

### Multi-Core Build Support

Build containers utilize multiple CPU cores when available:

- **CPU Detection**: Detect number of available CPU cores
- **Core Allocation**: Allocate multiple cores to build containers (e.g., `--cpus=$(nproc)` or proportional allocation)
- **Build Commands**: Use parallel build flags when supported:
  - Make: `make -j$(nproc)`
  - Cargo: `cargo build --jobs $(nproc)`
  - CMake: `cmake --build . -j$(nproc)`
- **Resource Limits**: Balance between parallel builds and per-build core allocation

### Test Image Creation

After successful builds, Docker images are created for test containers:

- **Image Contents**:
  - Build artifacts (compiled binaries, generated files, dependencies, etc.)
  - Source code
  - Test suites
  - Test dependencies (if needed)
- **Image Tagging**: Tagged with framework identifier and timestamp (e.g., `suitey-test-rust-20240115-143045`)
- **Dockerfile Generation**: Automatically generated Dockerfile includes:
  - Base image (same as build or test-specific base)
  - COPY commands for artifacts, source, and tests
  - Environment configuration
  - Working directory setup
- **Image Building**: Built using `docker build` with appropriate context
- **Image Verification**: Verified to contain all required components before use

## Parallel Execution

### Parallel Build Strategy

The Build Manager executes builds in parallel when:

1. **No Dependencies**: Builds have no dependencies on other builds
2. **Same Dependency Tier**: Builds are in the same dependency tier
3. **Resource Availability**: System resources (CPU, memory) allow parallel execution

### Execution Limits

- Limit parallel builds based on available CPU cores
- Prevent resource exhaustion
- Balance build speed with system stability

### Dependency Handling

- Builds with dependencies wait for prerequisite builds to complete
- Dependent builds start automatically when dependencies finish
- Build failures in dependencies prevent dependent builds from starting

## Status Reporting

### Build Status States

Builds progress through the following states:

- **`pending`**: Build requirement identified but not yet started
- **`building`**: Build container is running
- **`built`**: Build completed successfully
- **`build-failed`**: Build failed with errors

### Real-Time Updates

The Build Manager provides real-time status updates:

- **Dashboard Mode**: Updates build status in dashboard display
  - Shows which builds are in progress
  - Displays build duration
  - Indicates build failures immediately
- **Verbose Mode**: Streams build output directly to stdout/stderr
  - Includes build identification prefixes
  - Shows full build output as it occurs

### Status Data Structure

Each build status includes:

```
framework=rust
status=built
duration=5.7
start_time=2024-01-15T14:30:45Z
end_time=2024-01-15T14:30:50Z
container_id=abc123...
exit_code=0
cpu_cores_used=4
test_image_name=suitey-test-rust-20240115-143045
test_image_image_id=sha256:def456...
test_image_dockerfile_path=/tmp/suitey-12345/builds/rust/Dockerfile
output=...
error=
```

## Error Handling

### Build Failure Scenarios

The Build Manager handles various failure scenarios:

1. **Build Command Failure**
   - Container exits with non-zero exit code
   - Capture error output from container
   - Report failure with framework identifier
   - Include actionable error messages

2. **Container Launch Failure**
   - Docker daemon not available
   - Image pull failures
   - Resource constraints
   - Report clear error messages with resolution steps

3. **Artifact Extraction Failure**
   - Artifacts not found in expected locations
   - Permission issues when copying from container
   - Report errors and continue if possible (some frameworks may not require artifacts)

4. **Test Image Build Failure**
   - Dockerfile generation errors
   - Docker build failures
   - Image verification failures
   - Report clear error messages with Dockerfile/build output

5. **Dependency Failure**
   - Prerequisite build fails
   - Dependent builds are skipped
   - Report dependency chain and failure point

6. **Missing Build Dependencies**
   - Required build tools not available in container
   - Missing source files
   - Configuration errors
   - Report missing dependencies clearly

### Error Messages

Error messages should include:

- **Framework Identifier**: Which framework's build failed
- **Build Command**: What command was executed
- **Error Output**: Relevant error messages from build output
- **Container Information**: Container ID, image used
- **Actionable Guidance**: Suggestions for resolving the issue

### Failure Propagation

When a build fails:

1. **Immediate Reporting**: Report failure to dashboard/verbose formatters
2. **Build Abortion**: Stop remaining builds in current tier (if applicable)
3. **Test Prevention**: Return failure status to Project Scanner to prevent test execution
4. **Cleanup**: Clean up build containers and temporary resources
5. **Exit Code**: Set appropriate exit code (see Exit Codes section)

## Signal Handling

### SIGINT (Control+C) Handling

When SIGINT is received during build execution:

**First Control+C**:
- Send termination signals to all running build containers
- Wait for containers to terminate gracefully (with timeout, e.g., 10-30 seconds)
- Clean up all build containers
- Display message: "Gracefully shutting down builds..."
- Exit with appropriate exit code based on partial results

**Second Control+C** (during graceful shutdown):
- Immediately force-terminate all remaining containers using `docker kill`
- Force-remove all containers without waiting
- Display message: "Forcefully terminating builds..."
- Exit immediately

### Container Tracking

- Track all build container IDs for cleanup
- Maintain container registry for signal-based termination
- Ensure no orphaned containers remain after interruption

## Integration with Other Components

### Project Scanner

- **Receives**: Build requirements from Project Scanner
- **Provides**: Build results and artifact metadata to Project Scanner
- **Coordinates**: Build completion before test execution begins

### Suitey Modules

- **Uses**: Module's `get_build_steps()` method for build execution specifications
- **Uses**: Module's build detection results to determine build requirements
- **Provides**: Build status and test image metadata for module's test execution

### Dashboard/Verbose Formatters

- **Provides**: Real-time build status updates
- **Streams**: Build output for verbose mode
- **Updates**: Dashboard display with build progress

### Result Storage

- **Provides**: Structured build results storage (shared component)
- **Includes**: Build duration, status, output, artifacts

## Implementation Details

### Temporary Directory Structure

Build Manager uses temporary directories for:

- Build output files (for verbose mode streaming)
- Build result files (structured data)
- Intermediate build artifacts (before volume storage)
- Container logs

Structure:
```
/tmp/suitey-<pid>/
  builds/
    <framework-1>/
      output.txt
      result.txt
      artifacts/          # Extracted build artifacts
      Dockerfile          # Generated Dockerfile for test image
    <framework-2>/
      output.txt
      result.txt
      artifacts/
      Dockerfile
```

### Test Image Management

- Generate Dockerfiles for test images
- Build Docker images with descriptive tags
- Track image IDs for cleanup
- Store Dockerfile configurations in temporary directories
- Clean up test images after test execution completes (or on error)

### Container Naming

Use consistent naming for build containers:
- Format: `suitey-build-<framework>-<timestamp>-<random>`
- Example: `suitey-build-rust-20240115-143045-a1b2c3`
- Enables easy identification and cleanup

### Build Result Collection

Each build writes results to structured files:

- **Output File**: Raw build output (stdout/stderr) for verbose mode
- **Result File**: Flat data format with:
  - Build status
  - Duration
  - Exit code
  - CPU cores used
  - Test image metadata (name, ID, Dockerfile path)
  - Error messages (if any)

### Cross-Platform Considerations

- Use cross-platform temp directory APIs to access `/tmp` (or platform equivalent)
- Handle path separators correctly (Windows vs Unix)
- Ensure Docker commands work on all platforms
- Handle platform-specific Docker limitations

## Dependencies

### External Dependencies

- **Docker**: Required for containerized builds

### Internal Dependencies

- **Project Scanner**: Provides build requirements
- **Suitey Modules Registry**: Access to Suitey Modules for build specifications
- **Dashboard/Verbose Formatters**: For status reporting

### Filesystem Requirements

- **Limited Host Filesystem Access**: Build Manager only modifies `/tmp` for temporary files and build artifacts
- **Container Isolation**: All build operations occur within Docker containers
- **Temporary Artifact Storage**: Build artifacts are stored in `/tmp` before being packaged into Docker images

## Exit Codes

Build Manager affects overall exit codes:

- **Build Success**: Allows test execution to proceed (exit code determined by test results)
- **Build Failure**: Should result in exit code `1` (test execution prevented)
- **Test Image Build Failure**: Should result in exit code `1` (test execution prevented)
- **Build Manager Error**: Should result in exit code `2` (suitey error)

## Future Considerations

- Build caching to skip unnecessary rebuilds
- Incremental builds for faster iteration
- Test image caching and reuse
- Build artifact compression for storage efficiency
- Build dependency graph visualization
- Build performance metrics and optimization
- Support for build tools beyond Docker (Podman, etc.)
- Build artifact validation and verification
- Build configuration file support (`.suiteyrc`, `suitey.toml`)
- Multi-stage Dockerfile optimization
- Image layer caching strategies
