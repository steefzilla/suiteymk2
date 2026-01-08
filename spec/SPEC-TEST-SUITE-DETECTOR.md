# Test Suite Detector Specification

## Overview

Test Suite Detector is a core component of Suitey responsible for automatically finding test files and grouping them into distinct test suites after platforms have been identified. It is orchestrated by Project Scanner as the **second phase** of the execution workflow, operating **after** Platform Detector has identified which platforms are present in the project. Test Suite Detector uses Suitey Modules to find test files using platform-specific patterns and heuristics, enabling zero-configuration test detection across multiple languages and frameworks.

## Responsibilities

Test Suite Detector is responsible for:

1. **Test File Detection**: Finding test files for each detected platform using platform-specific patterns
2. **Suite Identification**: Grouping test files into distinct test suites (by platform, directory, or file)
3. **Test Counting**: Counting individual tests within each test file/suite
4. **Metadata Collection**: Gathering metadata about detected test suites (file paths, test counts, platform type, etc.)
5. **Result Aggregation**: Returning discovered test suites with metadata to Project Scanner
6. **Filesystem Read-Only Operations**: All detection operations are read-only and respect Suitey's filesystem isolation principle

## Architecture Position

Test Suite Detector operates as part of the main suitey process:

```
┌─────────────────────────────────────┐
│         suitey (main process)       │
├─────────────────────────────────────┤
│  Project Scanner (Orchestrator)     │
│  ├─ Platform Detector              │
│  │  └─ Suitey Modules Registry     │
│  ├─ Test Suite Detector             │ ← This component
│  └─ Build System Detector           │
│  ...                                │
└─────────────────────────────────────┘
```

### Relationship to Other Components

- **Project Scanner**: Project Scanner orchestrates Test Suite Detector as part of the scanning workflow. Test Suite Detector operates **after** Platform Detection completes and **before** Build System Detection.

- **Platform Detector**: Test Suite Detector uses the results from Platform Detector to determine which Suitey Modules to use for finding test files. Platform detection results inform which modules are available and should be used for detection.

- **Suitey Modules Registry**: Test Suite Detector uses Suitey Modules (via Suitey Modules Registry) to find test files. Each module implements language-specific detection logic that Test Suite Detector coordinates.

- **Build System Detector**: Build System Detection operates after Test Suite Detector completes. Build System Detection uses Suitey Modules to determine build requirements per platform, which may be informed by the detected test suites.

## Detection Process

The detection process follows this sequential workflow:

1. **Platform Detection Phase** (prerequisite, performed by Platform Detector):
   - Project Scanner calls Platform Detector to identify which platforms are present
   - Platform Detector uses the Suitey Modules Registry to detect platforms
   - Returns list of detected platforms with metadata

2. **Test Suite Detection Phase** (orchestrated by Project Scanner):
   - For **each** detected platform, Project Scanner uses the platform's module to detect test files
   - Each module implements platform-specific detection logic using:
     - Test directory patterns (`./test/`, `./tests/`, etc.)
     - File naming patterns: `test_*.*`, `*_test.*`, etc.
     - Framework-specific patterns (e.g., `#[cfg(test)]` for Rust, `@test` for BATS)
   - Test files are grouped into distinct test suites (by framework, directory, or file)
   - Test counts are calculated for each suite
   - Suite metadata is collected and returned to Project Scanner

### Critical Requirement: All Platforms

Test Suite Detector **must** detect test suites for **all** detected platforms, not just the first one. This ensures that multi-platform projects have all their test suites detected and available for execution.

## Detection Heuristics

Test Suite Detector uses multiple heuristics to identify test files, implemented through Suitey Modules:

### 1. Test Directory Patterns

Scans for common test directory patterns:
- `./test/`
- `./tests/`
- Framework-specific patterns (e.g., `./tests/bats/` for BATS)

### 2. File Naming Patterns

Identifies test files through naming conventions:
- `test_*.*` (e.g., `test_utils.rs`)
- `*_test.*` (e.g., `utils_test.rs`)
- `*.bats` - BATS test files (e.g., `suitey.bats`, `utils.bats`)

### 3. Platform-Specific Patterns

Each Suitey Module implements platform-specific discovery patterns:

- **Bash/BATS**: Discovers `.bats` files in common test directories (`./tests/bats/`, `./test/bats/`, etc.)
- **Rust**: Discovers unit tests in `src/` (files with `#[cfg(test)]` modules) and integration tests in `tests/` directory

## Platform-Specific Discovery Details

### Bash/BATS Detection

BATS (Bash Automated Testing System) test files are detected through:

1. **File Extension**: All `.bats` files in the project
2. **Directory Patterns**: Common BATS test directory structures:
   - `./tests/bats/` - Primary BATS test directory
   - `./test/bats/` - Alternative directory structure
   - `./tests/` - May contain `.bats` files directly
3. **File Content Patterns**: Files with `#!/usr/bin/env bats` or `#!/usr/bin/bats` shebang
4. **Test Function Patterns**: Files containing `@test` annotations

### Bash/BATS Suite Organization

BATS test suites are organized as:

- **Per-File Suites**: Each `.bats` file becomes a separate test suite
- **Suite Naming**: Suite name derived from filename (e.g., `suitey.bats` → `suitey`)
- **Test Counting**: Each `@test` annotation counts as one test
- **Helper Files**: `.bash` files in helper directories are not counted as test suites

### Rust Detection

Rust test detection involves multiple test types:

1. **Unit Tests**: Discovered in `src/` directory files
   - Files containing `#[cfg(test)]` modules
   - Files with `#[test]` function annotations
   - Test functions within test modules

2. **Integration Tests**: Discovered in `tests/` directory
   - Files named `*.rs` in the `tests/` directory
   - Each file becomes a separate integration test suite

3. **Doc Tests**: Discovered in source code documentation
   - Code examples in `///` or `//!` documentation comments
   - Marked with ````rust` code blocks

### Rust Suite Organization

Rust test suites are organized as:

- **Unit Test Suites**: Grouped by source file (e.g., `src/lib.rs` unit tests)
- **Integration Test Suites**: One suite per file in `tests/` directory
- **Doc Test Suites**: One suite per documented item
- **Test Counting**: Each `#[test]` function counts as one test

## Suite Grouping Strategies

Test Suite Detector uses different grouping strategies based on platform characteristics:

### 1. File-Based Grouping

- **BATS**: Each `.bats` file becomes a separate suite
- **Simple Frameworks**: One file = one suite

### 2. Directory-Based Grouping

- **Rust Integration Tests**: All files in `tests/` directory are separate suites
- **Multi-File Suites**: Related files grouped by directory

### 3. Module-Based Grouping

- **Rust Unit Tests**: Tests within a source file are grouped together
- **Module Organization**: Tests organized by source code modules

## Test Counting

Test Suite Detector counts individual tests within each suite:

### BATS Test Counting

- **Per-File Counting**: Count `@test` annotations in each `.bats` file
- **Helper Functions**: Functions without `@test` are not counted
- **Setup/Teardown**: Setup and teardown functions are not counted as tests

### Rust Test Counting

- **Unit Tests**: Count `#[test]` functions in `#[cfg(test)]` modules
- **Integration Tests**: Count `#[test]` functions in files within `tests/` directory
- **Doc Tests**: Count executable code examples in documentation

## Metadata Collection

For each detected test suite, Test Suite Detector collects:

- **Suite Identifier**: Unique name for the test suite
- **Platform Type**: Which platform the suite belongs to
- **File Paths**: List of files containing tests for this suite
- **Test Count**: Number of individual tests in the suite
- **Directory Context**: Directory containing the test files
- **Execution Requirements**: Any special execution requirements

## Result Aggregation

Test Suite Detector returns results to Project Scanner in a structured format:

- **Suite List**: Array of discovered test suites
- **Platform Association**: Which platform each suite belongs to
- **Metadata**: Additional information for each suite
- **Execution Context**: Information needed for test execution

## Error Handling

Test Suite Detector handles various error conditions:

### Detection Errors

1. **File Access Errors**: Cannot read test files or directories
2. **Parse Errors**: Cannot parse test file content
3. **Platform Mismatches**: Test files don't match expected platform patterns
4. **Permission Errors**: Insufficient permissions to access test files

### Recovery Strategies

When detection errors occur:

1. **Skip Problematic Files**: Continue detection with other files
2. **Partial Results**: Return successfully detected suites
3. **Error Reporting**: Report detection issues with details
4. **Fallback Behavior**: Use basic patterns when advanced parsing fails

## Performance Considerations

### Efficient Detection

Test Suite Detector optimizes performance through:

1. **Selective Scanning**: Only scan relevant directories and files
2. **Early Termination**: Stop scanning when sufficient information is found
3. **Caching**: Cache detection results for repeated scans
4. **Parallel Processing**: Process multiple files concurrently when possible

### Scalability

The detection system scales with project size:

1. **Incremental Detection**: Detect suites incrementally
2. **Memory Efficiency**: Process large projects without excessive memory usage
3. **File System Optimization**: Minimize file system operations

## Implementation Notes

### Module-Based Architecture

Test Suite Detector relies on Suitey Modules for:

1. **Detection Logic**: Platform-specific file and content patterns
2. **Test Counting**: Platform-specific test identification
3. **Suite Organization**: How to group tests into suites
4. **Metadata Extraction**: Platform-specific metadata collection

### Cross-Platform Compatibility

Discovery works across platforms through:

1. **Path Handling**: Platform-appropriate path separators and resolution
2. **File Encoding**: Handle different file encodings appropriately
3. **Case Sensitivity**: Respect platform file system case sensitivity
4. **Symbolic Links**: Proper handling of symbolic links

## Extensibility

### Adding New Platforms

To add support for new platforms:

1. **Create Module**: Implement discovery methods for the new platform
2. **Define Patterns**: Specify file patterns, directory structures, content patterns
3. **Test Counting**: Implement test counting logic for the platform
4. **Suite Grouping**: Define how tests should be grouped into suites

### Custom Discovery Rules

The system supports custom discovery rules:

1. **Pattern Extensions**: Add new file patterns and naming conventions
2. **Content Analysis**: Implement custom content analysis for test identification
3. **Suite Organization**: Define custom grouping strategies
4. **Metadata Rules**: Specify custom metadata collection rules

## Testing Considerations

### Detection Testing

Test Suite Detector requires comprehensive testing:

1. **Platform Coverage**: Test detection for all supported platforms
2. **Pattern Recognition**: Verify correct identification of test files
3. **Suite Organization**: Ensure proper grouping of tests into suites
4. **Test Counting**: Validate accurate test counting
5. **Error Handling**: Test error recovery and reporting

### Integration Testing

Detection integrates with other components:

1. **Platform Detector**: Test detection after platform detection
2. **Project Scanner**: Test full detection workflow
3. **Suitey Modules Registry**: Test module-based detection

## Future Considerations

- Support for additional platforms (Jest, pytest, etc.)
- Custom test suite organization rules
- Performance optimization for large projects
- Parallel discovery processing
- Test suite filtering and selection
- Discovery result caching and reuse
- Support for test suite configuration files
- Advanced test categorization and tagging
- Integration with IDEs and editors
- Discovery of test dependencies and requirements
