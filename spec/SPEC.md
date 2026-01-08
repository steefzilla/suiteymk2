# Suitey Specification

## Overview

Suitey is a cross-platform tool designed to automatically discover, build (if needed), and run tests locally from any project, regardless of the test framework or build system used. It eliminates the need to know which testing tools a project uses, how to build it, or how to configure them. Simply run `suitey.sh [DIRECTORY]` (e.g., `suitey.sh .` for the current directory) and it will detect build requirements, execute builds in containerized environments, and run all available test suites in parallel, providing a unified dashboard view of build and test execution status.

Example dashboard display:

```
SUITE            STATUS    TIME      |  QUEUE   PASS    FAIL    TOTAL  |  ERR   WARN
unit             passed    2.3s      |  0       45      0       45     |  0     0
integration      running   1.1s      |  0       12      0       45     |  0     0
e2e              pending             |  50      0       0       50     |  0     0
performance      failed    5.7s      |  0       8       2       10     |  1     2
```

## Competitive Analysis

### Existing Solutions

Several tools address parts of Suitey's functionality, but none provide the complete zero-config, universal test execution experience:

**Language-Specific Tools** (Tox, pytest, Jest, Mocha, etc.)
- **Limitation**: Work only within their specific language/framework ecosystem
- **Requirement**: Developers must know which tool to use and how to configure it
- **Suitey Advantage**: Automatically detects and uses the appropriate tool for any project

**Build Systems** (Bazel, Make, Gradle, Maven, etc.)
- **Limitation**: Require explicit build file configuration (BUILD files, Makefiles, etc.)
- **Requirement**: Developers must understand the build system and maintain configuration
- **Suitey Advantage**: Automatically detects build requirements and executes builds without configuration

**CI/CD Platforms** (Jenkins, CircleCI, GitHub Actions, etc.)
- **Limitation**: Server-based, require extensive configuration, not designed for local development
- **Requirement**: Complex setup, YAML/config files, remote execution
- **Suitey Advantage**: Local-first, zero-config, works immediately in any project directory

**Task Runners** (Task, Just, npm scripts, etc.)
- **Limitation**: Require manual task definitions, no automatic test discovery
- **Requirement**: Developers must define and maintain task configurations
- **Suitey Advantage**: Discovers and executes tests automatically without any configuration

**Domain-Specific Tools** (Playwright, Selenium, etc.)
- **Limitation**: Focused on specific testing domains (web, browser, etc.)
- **Requirement**: Setup and configuration for each tool
- **Suitey Advantage**: Unified interface for all test types across all domains

### Suitey's Unique Value Proposition

1. **Zero Configuration**: No setup required - works immediately in any project
2. **Universal Discovery**: Automatically detects tests across languages, frameworks, and build systems
3. **Unified Dashboard**: Single interface for all test types, regardless of underlying framework
4. **Automatic Building**: Detects and executes build steps without manual configuration
5. **Containerized Execution**: Consistent, isolated test environments without setup
6. **Local-First**: Designed for developer workflows, not just CI/CD pipelines
7. **Framework Agnostic**: Works with any project without requiring knowledge of its testing stack

### Target Use Cases

- **New Developer Onboarding**: Run `suitey.sh [DIRECTORY]` (e.g., `suitey.sh .`) to immediately see and execute all tests
- **Multi-Language Projects**: Unified test execution across different parts of a monorepo
- **Legacy Projects**: Test execution without understanding historical build/test setup
- **Rapid Prototyping**: Quick test execution without framework setup overhead
- **Code Reviews**: Easy test execution in any project being reviewed

## Requirements

- Docker is required for containerized builds and test execution
- Framework-specific tools are detected and used automatically (e.g., `bats`, `cargo`, etc.)
- Build tools are automatically detected and used when projects require building before testing
- Suitey will not modify the host filesystem except for `/tmp` (used for temporary files and build artifacts)

## Core Functionality

The core functionality follows a clear workflow: **Platform Detection** → **Test Suite Detection** → **Build System Detection** → **Execution**.

1. **Platform Detection & Suitey Modules System**
   - Automatically detects which platforms are present in the project using Suitey Modules
   - Each Suitey Module implements detection logic using heuristics:
     - Package manager files (`Cargo.toml`, etc.)
     - Platform-specific configuration files (`Cargo.toml`, etc.)
     - Directory structure patterns and file extensions
   - Verifies that required platform tools are available (e.g., `bats`, `cargo`)
   - Returns a list of detected platforms with metadata for downstream use
   - Falls back gracefully if platform-specific tools are not available

2. **Test Suite Detection**
   - After frameworks are detected, discovers test files and groups them into test suites
   - Uses Suitey Modules to find test files through framework-specific heuristics:
     - Test directory patterns (`./test/`, `./tests/`, etc.)
     - File naming patterns: `test_*.*`, `*_test.*`, etc.
     - Framework-specific patterns (e.g., `#[cfg(test)]` for Rust, `@test` for BATS)
   - Each test suite is identifiable as a distinct unit (by framework, directory, or file)
   - Framework-agnostic: works with Rust and BATS

3. **Build System Detection & Automation**
   - Automatically detects if a project requires building before tests can run
   - Uses Suitey Modules to determine build requirements per framework:
     - Build configuration files (`Makefile`, `CMakeLists.txt`, `Dockerfile`, etc.)
     - Package manager build scripts (`Cargo.toml`, etc.)
     - Source code patterns indicating compilation needs (compiled languages, etc.)
   - Automatically executes build steps in containerized environments before running tests
   - Build process:
     1. Uses base images with mounted volumes for building
     2. Starts build containers with multiple CPU cores when available
     3. Installs dependencies in build containers
     4. Builds with multiple cores when available
     5. On success, creates Docker images containing build artifacts, source code, and test suites
     6. Test containers use these pre-built images (no volume mounting needed)
   - Build steps run in parallel when multiple independent builds are detected
   - Build failures are reported clearly and prevent test execution

4. **Test Execution**
   - Uses Suitey Modules to execute tests with appropriate test runners:
     - Rust: `cargo test` (includes build step)
     - BATS: `bats <test-file>` (no build step required)

5. **Parallel Execution**
   - Runs all discovered test suites in parallel by default
   - Manages concurrent execution of multiple test processes
   - Handles process lifecycle and cleanup
   - Limits number of processes by number of CPU cores available
   - Each suite runs in isolation in Docker containers

6. **Single Suite Execution**
   - Option to run a single test suite
   - Validates that the specified suite exists before execution

7. **Output Modes**

   Both modes use the same execution engine and structured data collection. The difference is only in how results are presented.

   **Dashboard Mode (Default)**
   - Displays a real-time dashboard view when verbose is not specified
   - Dashboard shows:
     - Build status (when builds are in progress): `building`, `built`, `build-failed`
     - All test suites being executed
     - Current status of each suite (`pending`, `loading`, `running`, `passed`, `failed`, `error`)
     - Execution time for each suite
     - Number of tests queued
     - Number of tests passed
     - Number of tests failed
     - Total number of tests
     - Number of errors
     - Number of warnings
   - Provides a summary at the end including build and test results
   - After all tests complete, outputs all tests in order with stack traces for failures, errors, and (optionally) warnings

   **Verbose Mode**
   - Streams raw output from all test suites directly to stdout/stderr
   - Shows full test output without dashboard formatting
   - Useful for debugging and detailed inspection
   - Output is interleaved as test suites run in parallel (includes suite identification prefixes)
   - Interleaving is buffered by test suite and only output when a block is detected, with a fallback to output a whole buffer every 100ms. This is done to improve readability.
   - After all tests complete, outputs all tests in order with stack traces for failures, errors, and (optionally) warnings

8. **Report Generation & Local Hosting**
   - After test execution completes, automatically generates a comprehensive HTML report
   - Report includes:
     - Summary statistics (total tests, passed, failed, duration)
     - Build status and results (if builds were executed)
     - Detailed results for each test suite (status, duration, test counts)
     - Individual test results with pass/fail status
     - Test output and error messages for failed tests
     - Platform and module information
   - Report is served using a Docker container running nginx (or similar lightweight web server)
   - Uses a common Docker image (e.g., `nginx:alpine`) to host the report
   - Container mounts the report directory and serves it on a local port (default: 8080)
   - Displays a clickable link in the terminal (e.g., `http://localhost:8080/2024-01-15-14-30-45`)
   - Report container runs until user stops it (Ctrl+C) or explicitly terminates it
   - Report files are saved to `/tmp/suitey-reports/` directory for later viewing
   - Reports are timestamped and can be archived for historical comparison
   - If port is already in use, automatically selects the next available port

## Architecture

Suitey follows a **single-process architecture** with platform detection and Suitey Modules system:

```
┌─────────────────────────────────────┐
│         suitey (main process)       │
├─────────────────────────────────────┤
│  Project Scanner (Orchestrator)     │
│  ├─ Platform Detector               │
│  ├─ Test Suite Detector              │
│  └─ Build System Detector           │
│  Build Manager                      │
│  Parallel Execution Manager         │
├─────────────────────────────────────┤
│  Shared Components:                 │
│  • Suitey Modules Registry          │
│  • Result Storage (structured data)│
├─────────────────────────────────────┤
│  Presentation Layer:                │
│  • Dashboard Formatter              │
│  • Verbose Formatter                │
└─────────────────────────────────────┘
```

### Component Relationships

The architecture follows a hierarchical orchestration pattern:

1. **Project Scanner** is the primary orchestrator component responsible for:
   - Coordinating overall project analysis
   - Calling Platform Detector to identify platforms
   - Performing Test Suite Detection to find and group test files
   - Performing Build System Detection to identify build requirements
   - Aggregating results from all sub-components

2. **Platform Detector** is a specialized component called by Project Scanner:
   - Identifies which platforms are present in the project
   - Uses the Suitey Modules Registry to access platform-specific detection logic
   - Returns platform detection results to Project Scanner
   - Platform detection results inform both Test Suite Detection and Build System Detection

3. **Suitey Modules Registry** is a shared component:
   - Maintains a registry of Suitey Modules (Rust, Bash, etc.)
   - Provides language-specific detection, discovery, and execution logic
   - Used by Platform Detector, Project Scanner and Build System Detector to coordinate module-based detection
   - Each module implements detection, discovery, build detection, and execution methods

4. **Test Suite Detection** is a component orchestrated by Project Scanner:
   - Operates after Platform Detector has identified available platforms (Test Suite Detector)
   - Uses Suitey Modules (via Suitey Modules Registry) to find test files using platform-specific patterns
   - Groups test files into distinct test suites
   - Returns discovered test suites with metadata to Project Scanner

5. **Build System Detector** is a responsibility of Project Scanner:
   - Identifies if and how the project needs to be built before testing
   - Uses Suitey Modules to determine build requirements per platform
   - May use Platform Detector results to inform build detection
   - Returns build requirements to Project Scanner for coordination with Build Manager

### Key Architectural Principles

1. **Single Process**: The main suitey process directly manages all test execution.

2. **Cross-Platform**: An implementation uses platform-specific process management, file I/O, and terminal interaction.

3. **Framework-Agnostic**: Suitey doesn't depend on any specific test framework. It detects what's available and uses the appropriate tools.

4. **Suitey Modules Pattern**: Suitey Modules provide a consistent interface for language-specific operations (detection, discovery, build detection, execution, and parsing). This enables Suitey to work with any language and test framework without hardcoding specific logic. See Suitey Modules in Technical Considerations for details.

5. **Graceful Degradation**: If a framework's tools aren't available, Suitey skips that framework and continues with others.

6. **Containerized Execution**: Docker is used for:
   - Building projects in isolated, reproducible environments
   - Running tests in containers with consistent dependencies
   - Ensuring cross-platform compatibility
   - Isolating build artifacts and test outputs

7. **Filesystem Isolation**: Suitey will not modify the host filesystem except for `/tmp`. All operations are performed within Docker containers, with temporary files and artifacts stored in `/tmp`.

8. **Structured Data Collection**: Test results are collected as structured data internally (status, test counts, execution time, output streams), not by parsing text output.

9. **Separation of Concerns**: Execution logic is separate from presentation logic. The same execution engine feeds both dashboard and verbose modes.

10. **Real-time Updates**: Results are collected and displayed as tests execute, not after completion.

## Dependencies

### External Dependencies

- **Docker**: Required for containerized builds and test execution. Must be installed and available.
- **Framework-Specific Tools**: Detected automatically and used within containers as needed (e.g., `bats`, `cargo`, etc.)

### Implementation Dependencies

- **Standard Library Preferred**: The implementation should prefer standard library features where possible
- **Minimal External Dependencies**: External libraries should be kept to a minimum and only used when necessary for cross-platform compatibility or platform detection
- The tool should be distributable as a single executable or self-contained script

## Technical Considerations

### Execution Workflow

The execution follows a sequential workflow orchestrated by Project Scanner:

1. **Platform Detection Phase**: Project Scanner calls Platform Detector, which uses the Suitey Modules Registry to identify which platforms are present in the project. Each module implements platform-specific detection logic using heuristics (package manager files, configuration files, directory patterns, etc.).

2. **Test Suite Detection Phase**: For each detected platform, Project Scanner uses the platform's module to detect test files. Each module knows how to find test files for its platform using platform-specific patterns (directory structures, file naming conventions, etc.). Test files are grouped into distinct test suites.

3. **Build System Detection Phase**: Project Scanner uses Suitey Modules to determine if building is required before testing. Each module implements build detection logic and specifies build commands if needed. Build requirements are determined per platform.

4. **Build Phase** (if needed): Build steps execute in Docker containers to ensure consistent, isolated environments. The build process:
   - Uses base images with mounted volumes for building
   - Allocates multiple CPU cores to build containers when available
   - Installs dependencies and builds the project
   - On successful build, creates Docker images containing build artifacts, source code, and test suites
   - Test containers use these pre-built images (self-contained, no volume dependencies)
   - Build steps can run in parallel when multiple independent builds are detected

5. **Execution Phase**: Test suites run in Docker containers using their native test runners. Each Suitey Module determines the execution method (Docker container, etc.) and parses output to extract structured results.

### Suitey Modules

Suitey Modules are the core abstraction that enables language-agnostic test execution. Each module implements a consistent interface:

- **Detection**: Determines if this language/framework is present in the project using language-specific heuristics
- **Discovery**: Finds test files/suites for this language using language-specific patterns
- **Build Detection**: Determines if building is required before testing
- **Build Steps**: Specifies how to build the project (if needed) in a containerized environment
- **Execution**: Runs tests using the language's native tools in containers
- **Parsing**: Extracts test results (counts, status, output) from framework output

Supported languages:
- Rust: cargo test
- Bash/Shell: BATS

### Containerized Execution

- Test suites run in Docker containers using their native test runners (e.g., `cargo test`, `bats`)
- Builds execute in Docker containers to ensure:
  - Consistent build environments across platforms
  - Proper dependency isolation
  - Reproducible builds
- Execution returns structured data:
  - Exit code (from test runner)
  - Test counts (total, passed, failed) - extracted from test framework output
  - Execution time
  - Output stream (stdout/stderr captured from container)
- Results are collected as tests execute, not after completion
- Language-specific tools are detected at runtime within containers; missing tools result in skipped languages with clear error messages

### Error Handling

- Handle cases where no test directories exist
- Handle cases where no test suites are found
- Handle cases where `--suite` specifies a non-existent suite
- Handle build failures gracefully with clear error messages
- Handle test suite execution failures gracefully
- Handle cases where framework-specific tools are not available in containers
- Handle cases where Docker is not installed (required dependency)
- Handle Docker daemon connectivity issues
- Handle cases where build dependencies are missing
- Handle cases where report directory cannot be created or written to
- Handle cases where report server container cannot be started (fallback to console output only)
- Handle cases where report server port is already in use (automatically select next available port)
- Provide clear error messages indicating:
  - Which frameworks were detected
  - Which builds were attempted and their status
  - Which test suites were skipped and why
  - Build errors with actionable information
  - Report generation failures (with fallback to console output only)

### Signal Handling

- When a Control+C (SIGINT) signal is received during execution:
  - **First Control+C**:
    - Abort all running test suites (send termination signals to all test containers)
    - Wait for all test suites to terminate gracefully (with a reasonable timeout)
    - Clean up all Docker containers (test containers, build containers, and any related containers)
    - Display a message indicating graceful shutdown is in progress
    - Exit with appropriate exit code based on partial results (if any)
  - **Second Control+C** (if received during graceful shutdown):
    - Immediately force-terminate all remaining containers using `docker kill`
    - Force-remove all containers without waiting
    - Display a message indicating forceful termination
    - Exit immediately
- Signal handling applies to all phases of execution:
  - During build phase: abort builds, clean up build containers
  - During test execution: abort tests, clean up test containers
  - During report generation: abort report generation, clean up any containers
  - During report server hosting: stop report server container and exit
- Graceful termination timeout should be reasonable (e.g., 10-30 seconds) to prevent indefinite waiting
- All Docker containers created by suitey should be tracked and cleaned up on interruption

### Command-Line Interface

Suitey is invoked via the `suitey.sh` script:

**Basic Usage:**
- `suitey.sh` - Shows help text (default behavior when no arguments provided)
- `suitey.sh [DIRECTORY]` - Runs Suitey on the specified directory (e.g., `suitey.sh .` to run on current directory)
- `suitey.sh --help` or `suitey.sh -h` - Shows help text
- `suitey.sh --version` or `suitey.sh -v` - Shows version information

**Directory Argument:**
- When a directory path is provided as an argument, Suitey will run on that directory
- The directory path can be relative (e.g., `.`, `../other-project`) or absolute (e.g., `/path/to/project`)
- If no directory is specified, Suitey shows help text
- The directory must exist and be readable

**Options:**
- `-h, --help` - Display help information and exit
- `-v, --version` - Display version information and exit

**Future Options** (to be implemented in later phases):
- `--suite SUITE_NAME` - Run only the specified test suite
- `--verbose` - Enable verbose output

### Exit Codes

- `0`: All test suites passed
- `1`: One or more test suites failed
- `2`: Error in suitey itself (e.g., invalid arguments, no tests found)

## Implementation Notes

### Data Collection Strategy

The tool collects structured data from test executions using temporary files.

#### Temporary Files

Each test suite writes its results to temporary files in `/tmp`:

- **Output file**: Raw test output (stdout/stderr) for verbose mode
- **Result file**: Structured data (exit code, test counts, execution time)

#### Data Extraction

Each Suitey Module implements parsing logic to extract test results from platform output. Test counts are extracted by parsing platform-specific output patterns (e.g., "✓ 5 passed, ✗ 2 failed", "Tests: 10 passed, 2 failed"). Exit codes determine overall pass/fail status. This module-based parsing approach supports multiple platforms with different output formats.

### Report Generation & Hosting

#### Report Format

Reports are generated as standalone HTML files with embedded CSS and JavaScript for portability:
- **Summary Section**: Overall statistics, build status, execution time
- **Test Suites Section**: Detailed breakdown per suite with expandable sections
- **Individual Test Results**: Pass/fail status, duration, error messages
- **Timeline Visualization**: Visual representation of test execution order and duration
- **Platform Information**: Which modules were used, detected platforms
- **Build Information**: Build steps executed, build artifacts, build duration

#### Report Storage

- Reports are saved to `/tmp/suitey-reports/` directory (created if it doesn't exist)
- Filename format: `report-YYYY-MM-DD-HH-MM-SS.html` (timestamped)
- Previous reports are preserved for historical comparison
- Reports are self-contained (no external dependencies)

#### Docker-Based Report Hosting

- After report generation, launches a Docker container using a common web server image (e.g., `nginx:alpine`)
- Container mounts the `/tmp/suitey-reports/` directory and serves it via HTTP
- Server runs on localhost only (127.0.0.1) for security
- Default port is 8080, automatically selects next available port if in use
- Container runs in detached mode and continues until explicitly stopped
- Terminal displays clickable link (if supported) or plain URL for easy access
- Container ID is tracked for cleanup on exit (if user stops suitey)
- Uses minimal resource footprint with alpine-based images

### Parallel Execution Pattern

1. **Initialization**:
   - Create a temporary directory for storing results and build artifacts in `/tmp` using cross-platform temp directory APIs and register cleanup on exit

2. **Discovery**:
   - Project Scanner orchestrates Platform Detection, Test Suite Detection, and Build System Detection (see Technical Considerations above)
   - For each detected platform, use its module to detect test suites
   - Collect all discovered suites with their execution metadata
   - Determine build requirements for each platform

3. **Build Phase**:
   - For each framework that requires building:
     - Determine build steps using Suitey Module
     - Launch build containers in parallel (when builds are independent)
     - Allocate multiple CPU cores to build containers when available
     - Track build progress and collect build artifacts
     - On successful build, create Docker images containing:
       - Build artifacts (compiled binaries, generated files, etc.)
       - Source code
       - Test suites
     - Generate Dockerfile for test containers
   - Wait for all required builds to complete before proceeding
   - Report build failures immediately and abort test execution
   - Link test suites to their corresponding build artifacts (if any)

4. **Test Execution**:
   - Launch all test suites in parallel, tracking their container IDs
   - Each suite execution:
     - Records start time
     - Uses pre-built test image (containing artifacts, source, and tests) or base image (if no build required)
     - Test containers start with everything ready (no volume mounting needed)
     - Executes using Suitey Module's execution method (Docker container, etc.)
     - Captures exit code from container
     - Calculates duration
     - Extracts test counts from output (using module's parser)
     - Writes structured results to a suite-specific result file

5. **Result Monitoring**:
   - **Verbose mode**: Stream output directly from temporary output files as builds and tests run
   - **Dashboard mode**: Poll the `/tmp` directory, reading result files as they become available and updating the display until all containers complete
   - Show build status in dashboard when builds are in progress

6. **Completion**:
   - Generate comprehensive HTML report from collected test results
   - Save report to `/tmp/suitey-reports/` directory with timestamp
   - Launch Docker container with nginx (or similar) to serve the report
   - Container mounts report directory and serves on available port (default: 8080)
   - Display final summary in terminal including:
     - Overall test results
     - Link to view detailed report (e.g., `View report: http://localhost:8080/report/2024-01-15-14-30-45`)
     - Instructions to stop the report server (Ctrl+C or `docker stop <container-id>`)
   - **Post-Completion Test Output**: After all tests complete, output all tests in order:
     - List all tests executed (grouped by test suite)
     - For each test: display test name, status (passed/failed/error/warning)
     - For failed tests: display full stack trace and error output
     - For error tests: display full stack trace and error output
     - For warning tests (optional): display warning message and stack trace if configured
     - Tests are displayed in execution order within each suite
     - Suites are displayed in the order they were executed
   - Clean up temporary files and build artifacts (test/build containers are cleaned up, but report container and files persist)
   - Report container continues running until user stops it, allowing report viewing after execution completes

## Future Considerations

- Test suite configuration files (`.suiteyrc`, `suitey.toml`)
- Filtering tests within suites
- Watch mode (re-run on file changes)
- Test coverage reporting
- Custom test runners and modules
- CI/CD integration modes
- JSON output mode for programmatic consumption
- Framework-specific optimizations and caching
