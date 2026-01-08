# Project Scanner Specification

## Overview

The Project Scanner is the primary orchestrator component of Suitey responsible for coordinating project analysis, test suite detection, and build requirement identification. It orchestrates the workflow: **Platform Detection** → **Test Suite Detection** → **Build System Detection**. It operates through a combination of heuristics, file system scanning, and coordination with specialized components (Platform Detector, Test Suite Detector, Build System Detector) to provide zero-configuration test detection.

## Responsibilities

The Project Scanner is responsible for:

1. **Orchestration**: Coordinating the overall project analysis workflow
2. **Platform Detection Coordination**: Calling Platform Detector to identify which platforms are present
3. **Test Suite Detection**: Orchestrating Test Suite Detector to find and group test files after platforms are detected
4. **Build System Detection**: Identifying if and how the project needs to be built before testing
5. **Result Aggregation**: Aggregating results from all sub-components into a unified output
6. **Filesystem Read-Only Operations**: All scanning operations are read-only and respect Suitey's filesystem isolation principle

## Architecture Position

The Project Scanner operates as part of the main suitey process:

```
┌─────────────────────────────────────┐
│         suitey (main process)       │
├─────────────────────────────────────┤
│  Project Scanner (Orchestrator)     │ ← This component
│  ├─ Platform Detector              │
│  │  └─ Suitey Modules Registry     │
│  ├─ Test Suite Detector             │
│  └─ Build System Detector           │
│  ...                                │
└─────────────────────────────────────┘
```

## Test Suite Detection

Test Suite Detector is orchestrated by Project Scanner and operates **after** Platform Detector has identified which platforms are present in the project. It uses Suitey Modules to find test files using platform-specific patterns.

### Detection Process

The detection process follows this workflow:

1. **Platform Detection Phase** (performed by Platform Detector):
   - Project Scanner calls Platform Detector to identify which platforms are present
   - Platform Detector uses the Suitey Modules Registry to detect platforms
   - Returns list of detected platforms with metadata

2. **Test Suite Detection Phase** (orchestrated by Project Scanner):
   - For each detected platform, Project Scanner uses the platform's module to detect test files
   - Each module implements platform-specific detection logic using:
     - Test directory patterns (`./test/`, `./tests/`, etc.)
     - File naming patterns: `test_*.*`, `*_test.*`, etc.
     - Framework-specific patterns (e.g., `#[cfg(test)]` for Rust, `@test` for BATS)
   - Test files are grouped into distinct test suites (by framework, directory, or file)

### Platform-Specific Detection

Each Suitey Module implements detection logic specific to its platform:

- **BATS**: Discovers `.bats` files in common test directories (`./tests/bats/`, `./test/bats/`, etc.)
- **Rust**: Discovers unit tests in `src/` (files with `#[cfg(test)]`) and integration tests in `tests/`

### Framework-Agnostic Approach

The scanner works with the following frameworks:
- Rust (cargo test)
- Bash/Shell (BATS - Bash Automated Testing System)

## Platform Detection Coordination

Project Scanner orchestrates Platform Detection by calling the Platform Detector component. Platform Detection happens **before** Test Suite Detection, as the detected platforms inform which modules to use for test file detection.

### Workflow

1. **Project Scanner calls Platform Detector**: Platform Detector uses the Suitey Modules Registry to identify which platforms are present in the project
2. **Platform Detector returns results**: Returns list of detected platforms with metadata (confidence levels, binary availability, etc.)
3. **Project Scanner uses results**: The detected platforms inform:
   - Which modules to use for Test Suite Detection
   - Which modules to use for Build System Detection
   - Platform-specific metadata needed for execution

For detailed information about Platform Detection, see the Platform Detector Specification.

## Build System Detection

### Detection Heuristics

The scanner detects build requirements through:

#### 1. Build Configuration Files
- `Makefile` - Make-based builds
- `CMakeLists.txt` - CMake builds
- `Dockerfile` - Docker-based builds
- `build.sh`, `build.bat` - Custom build scripts

#### 2. Package Manager Build Scripts
- `Cargo.toml` build configuration

#### 3. Source Code Patterns
- Compiled languages requiring build steps

### Build Detection Process

1. **Scan for Build Indicators**: Check for build configuration files and patterns
2. **Suitey Module Analysis**: Each module determines if building is required
3. **Build Step Identification**: Determine specific build commands needed
4. **Dependency Analysis**: Identify build dependencies and requirements

### Build Requirements by Platform

- **Rust**: `cargo build` (often implicit in `cargo test`)
- **Bash/BATS**: Typically no build required (bash scripts are interpreted), but may need `bats` binary installation

## Integration with Suitey Modules System

The Project Scanner works in conjunction with the Suitey Modules System through the following workflow:

1. **Platform Detection**: Project Scanner calls Platform Detector, which uses the Suitey Modules Registry to identify which platforms are present
2. **Test Suite Detection**: For each detected platform, Project Scanner uses the platform's module to detect test files using platform-specific patterns
3. **Build System Detection**: Project Scanner uses platform modules to determine build requirements per platform
4. **Result Aggregation**: Project Scanner aggregates results from all phases (platform detection, test suite detection, build detection) into a unified output

The Suitey Modules Registry provides a consistent interface for all language-specific operations (detection, discovery, build detection, execution, and parsing).

## Output

The Project Scanner produces aggregated results from all orchestrated components:

1. **Detected Platforms** (from Platform Detector):
   - List of platforms found in the project
   - Platform metadata (confidence levels, binary availability, etc.)

2. **Test Suites** (from Test Suite Detector):
   - Collection of discovered test suites with metadata:
     - Suite name/identifier
     - Platform type
     - Test files included
     - Test counts
     - Execution metadata

3. **Build Requirements** (from Build System Detector):
   - List of build steps needed before testing
   - Build commands per framework
   - Build dependencies

4. **Project Structure**: Understanding of project organization

## Error Handling

The scanner handles:

- **No Test Directories**: Projects without test directories
- **No Test Suites Found**: Projects with no discoverable tests
- **Missing Platform Tools**: Platforms detected but tools not available (e.g., `bats` command not found)
- **Invalid Project Structure**: Malformed or unusual project layouts
- **Conflicting Platforms**: Multiple platforms detected in same project
- **Missing Dependencies**: Platform-specific dependencies not available (e.g., BATS binary not installed)

All errors are reported with clear, actionable messages indicating:
- Which platforms were detected
- Which test suites were found
- Which platforms were skipped and why
- What build steps are required
- What dependencies need to be installed (e.g., `bats` for Bash/BATS projects)

## Performance Considerations

- **Efficient Scanning**: Uses optimized directory traversal
- **Parallel Detection**: Platform detection can occur in parallel where possible
- **Caching Opportunities**: Results can be cached for repeated scans
- **Minimal I/O**: Reduces file system operations where possible

## Implementation Notes

### Scanning Strategy

1. **Top-Down Approach**: Start from project root and scan recursively
2. **Early Termination**: Stop scanning subdirectories when framework is identified
3. **Pattern Matching**: Use efficient pattern matching for file names
4. **Configuration Parsing**: Parse configuration files to extract test locations

### Cross-Platform Considerations

- Use cross-platform file system APIs
- Handle different path separators (`/` vs `\`)
- Respect case-sensitive vs case-insensitive file systems
- Handle symbolic links appropriately

### Extensibility

The scanner is designed to be extensible:
- New Suitey Modules can be added without modifying core scanner logic
- New heuristics can be added for additional project types
- Custom detection patterns can be registered
- Platform-specific detection logic is isolated in modules

## BATS-Specific Considerations

### BATS Detection

BATS (Bash Automated Testing System) is a testing framework for bash scripts. The scanner detects BATS projects through:

1. **File Extension**: Presence of `.bats` files in the project
2. **Directory Patterns**: Common BATS test directory structures:
   - `./tests/bats/` - Common pattern for BATS test organization
   - `./test/bats/` - Alternative directory structure
   - `./tests/` - May contain `.bats` files directly
3. **Binary Detection**: Checks for `bats` command availability in the system
4. **Shebang Patterns**: Files with `#!/usr/bin/env bats` or `#!/usr/bin/bats` shebang

### BATS Test File Structure

BATS test files typically:
- Have `.bats` extension
- Start with `#!/usr/bin/env bats` shebang
- Contain `@test` annotations for test cases
- May include helper files in `helpers/` subdirectories

### BATS Execution Requirements

- **No Build Step**: BATS tests are bash scripts and typically don't require compilation
- **Binary Dependency**: Requires `bats` binary to be installed (can be installed via package managers or from source)
- **Helper Support**: BATS projects may use helper files in `tests/bats/helpers/` or similar directories
- **Test Detection**: All `.bats` files in detected test directories are considered test suites

### Bash Suitey Module Considerations

The Bash Suitey Module should:
- Detect `.bats` files and `bats` binary availability for Bash language projects
- Discover all `.bats` files in test directories
- Handle helper file dependencies (may need to be available in test execution context)
- Execute tests using `bats <test-file>` or `bats <test-directory>`
- Parse BATS output to extract test results (pass/fail counts, test names)
- Support parallel execution of multiple BATS test files
- Handle cases where `bats` binary is not available (skip with clear error message)

### BATS Project Patterns

Common BATS project structures:
```
project/
├── tests/
│   └── bats/
│       ├── helpers/
│       │   └── helper.bash
│       ├── suitey.bats
│       └── utils.bats
└── suitey.sh
```

The scanner should recognize these patterns and group BATS files appropriately, potentially treating each `.bats` file as a separate test suite or grouping them by directory.
