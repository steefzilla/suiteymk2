# Suitey Implementation Plan (TDD Methodology)

This document outlines the implementation plan for Suitey following Test-Driven Development (TDD) methodology. Each phase follows the Red-Green-Refactor cycle: write failing tests first, implement minimal code to pass, then refactor.

## TDD Workflow

For each component:
1. **Red**: Write failing tests that define the desired behavior
2. **Green**: Implement minimal code to make tests pass
3. **Refactor**: Improve code quality while keeping tests green
4. **Repeat**: Move to next test/feature

### Completion Requirement

**A step is only considered complete when all tests pass with no failures.**

Before marking any step (Red, Green, or Refactor) as complete, you must:
- Run `bats -rj 16 tests` (or equivalent: `bats -r -j 16 tests`)
- Verify that all tests pass with zero failures
- Ensure no regressions were introduced

This requirement applies to all phases and ensures code quality and test coverage throughout the implementation.

## Phase 0: Environment Setup and Basic Script Foundation (Prerequisites)

### 0.1 Environment Test Suite

**Goal**: Validate that the development and runtime environment is properly configured.

#### TDD Steps:

**0.1.1 Environment Validation Tests**
*Create functions to check Bash version, Docker installation, and required directories.*
- [x] **Red**: Write test `tests/bats/unit/environment.bats` for environment validation
  - Test: Bash version is 4.0 or higher
  - Test: Docker is installed and accessible
  - Test: Docker daemon is running
  - Test: Required directories exist (`src/`, `tests/bats/`, `mod/`)
  - Test: `/tmp` directory is writable
  - Test: Required test dependencies are available (BATS, bats-support, bats-assert)
- [x] **Green**: Implement environment validation checks in `src/environment.sh`
  - Use existing `check_bash_version()`, `check_docker_installed()`, etc.
  - Ensure all checks return appropriate exit codes
- [x] **Refactor**: Improve error messages, add helpful setup instructions

**0.1.2 Filesystem Isolation Validation**
*Verify that Suitey only writes to /tmp and doesn't modify project directories.*
- [x] **Red**: Write tests for filesystem isolation
  - Test: Can create files in `/tmp`
  - Test: Cannot write to project directory (read-only test)
  - Test: Temporary directories can be created in `/tmp`
  - Test: Environment checks respect filesystem isolation principle
- [x] **Green**: Implement filesystem isolation validation
- [x] **Refactor**: Improve validation logic

**Acceptance Criteria**:
- All environment checks pass
- Clear error messages for missing dependencies
- Filesystem isolation verified
- Tests can be run independently

---

### 0.2 Build System (`build.sh`)

**Goal**: Create a build system to compile/bundle all source scripts into a single `suitey.sh` executable.

**Note**: `suitey.sh` does NOT exist before this phase. It is created by the build system.

#### TDD Steps:

**0.2.1 Build Script Creation**
*Create the build.sh script with basic structure and help functionality.*
- [x] **Red**: Write test `tests/bats/unit/build_script.bats` for build script
  - Test: `build.sh` file exists
  - Test: `build.sh` is executable
  - Test: Build script has shebang (`#!/usr/bin/env bash`)
  - Test: Running `./build.sh --help` shows help text
  - Test: Running `./build.sh` without args builds suitey.sh
- [x] **Green**: Create `build.sh` with basic structure
  - Add shebang
  - Add help/usage functions
  - Make executable
- [x] **Refactor**: Improve script structure, add error handling

**0.2.2 Source File Discovery**
*Implement logic to find and list all source files and modules for bundling.*
- [x] **Red**: Write tests for source file discovery
  - Test: Build script can list all source files in `src/`
  - Test: Build script can list all modules in `mod/`
  - Test: Build script validates required files exist
  - Test: Build script handles missing files gracefully
  - Test: Build script respects dependency order (dependencies first)
- [x] **Green**: Implement source file discovery logic
  - Scan `src/` directory for `.sh` files
  - Scan `mod/` directory for modules (recursively)
  - Validate file existence
  - Determine dependency order (if dependency tracking exists)
- [x] **Refactor**: Optimize file discovery, add dependency analysis

**0.2.3 Script Bundling**
*Concatenate all source files and modules into a single executable suitey.sh file.*
- [x] **Red**: Write tests for script bundling
  - Test: Build script creates bundled output file `suitey.sh`
  - Test: Bundled script contains all source files from `src/`
  - Test: Bundled script contains all modules from `mod/`
  - Test: Bundled script has correct shebang (`#!/usr/bin/env bash`)
  - Test: Bundled script is executable
  - Test: Source files are included in correct order (dependencies first)
  - Test: Modules are included after source files
  - Test: No duplicate includes (each file included once)
- [x] **Green**: Implement script bundling
  - Concatenate source files in dependency order
  - Include modules in bundle
  - Add header with version/metadata
  - Add footer with main execution call
  - Make output executable
- [x] **Refactor**: Improve bundling logic, optimize file order, handle edge cases

**0.2.4 Build Output Validation**
*Validate that the generated suitey.sh has correct syntax, is executable, and contains expected functions.*
- [x] **Red**: Write tests for build output validation
  - Test: Bundled `suitey.sh` is valid Bash syntax (use `bash -n`)
  - Test: Bundled `suitey.sh` can be executed
  - Test: Bundled `suitey.sh` has correct file size (not empty, reasonable size)
  - Test: Bundled `suitey.sh` contains expected functions
  - Test: Bundled `suitey.sh` maintains filesystem isolation (only `/tmp`)
- [x] **Green**: Implement build validation
  - Check Bash syntax with `bash -n`
  - Verify script is executable
  - Validate script structure
- [x] **Refactor**: Improve validation, add more comprehensive checks

**0.2.5 Build Artifacts Management**
*Manage build output files, cleanup temporary files, and support custom output paths.*
- [x] **Red**: Write tests for build artifacts
  - Test: Build creates output `suitey.sh` in project root (or specified location)
  - Test: Build cleans up temporary files in `/tmp`
  - Test: Build can specify output directory
  - Test: Build can specify output filename
  - Test: Build respects filesystem isolation (only writes to project root and `/tmp`)
- [x] **Green**: Implement artifact management
  - Generate output filename (with optional version/timestamp)
  - Clean up temporary files in `/tmp`
  - Support custom output paths
- [x] **Refactor**: Improve artifact management, add versioning support

**0.2.6 Build Options and Flags**
*Add command-line options like --output, --name, --version, --clean, and --verbose to build.sh.*
- [x] **Red**: Write tests for build options
  - Test: `./build.sh --output /path/to/output` sets output path
  - Test: `./build.sh --name suitey` sets output name
  - Test: `./build.sh --version 1.0.0` includes version in bundle
  - Test: `./build.sh --clean` cleans output before build
  - Test: `./build.sh --verbose` shows detailed build output
  - Test: `./build.sh --help` shows help text
- [x] **Green**: Implement build options
  - Parse command-line arguments
  - Apply options to build process
  - Add verbose logging
  - Add help text
- [x] **Refactor**: Improve option handling, add more options

**0.2.7 Build Process Integration**
*Verify the complete build process works end-to-end and creates a functional suitey.sh executable.*
- [x] **Red**: Write integration test `tests/bats/integration/build_process.bats`
  - Test: Full build process creates working `suitey.sh` executable
  - Test: Built `suitey.sh` contains all source files
  - Test: Built `suitey.sh` contains all modules
  - Test: Build process respects filesystem isolation (only writes to project root and `/tmp`)
- [x] **Green**: Ensure build process works end-to-end
- [x] **Refactor**: Optimize build process, improve error messages

**Acceptance Criteria**:
- `build.sh` exists and is executable
- Build script creates self-contained `suitey.sh` executable
- Built `suitey.sh` contains all source files and modules
- Built `suitey.sh` is valid Bash and runs correctly
- Build process is documented
- Build respects filesystem isolation (only project root and `/tmp`)
- Comprehensive unit and integration tests prevent regression

---

### 0.3 Basic Script Foundation (`suitey.sh`)

**Goal**: Create the main entry point script with basic help functionality.

**Note**: `suitey.sh` is created by `build.sh` in Phase 0.2. These tests verify the built script works correctly.

#### TDD Steps:

**0.3.1 Script Existence and Executability**
*Verify that build.sh creates suitey.sh with correct permissions and shebang.*
- [x] **Red**: Write test `tests/bats/unit/suitey_basic.bats` for script basics
  - Test: `suitey.sh` file exists (after build)
  - Test: `suitey.sh` is executable
  - Test: Script has shebang (`#!/usr/bin/env bash`)
  - Test: Script can be executed without errors
- [x] **Green**: Ensure `build.sh` creates `suitey.sh` with correct structure
  - Verify build output has shebang
  - Verify build output is executable
- [x] **Refactor**: Ensure proper permissions, shebang correctness

**0.3.2 Help Text Display**
*Implement --help and -h options to display usage information and exit with code 0.*
- [x] **Red**: Write tests for help functionality
  - Test: Running `./suitey.sh --help` exits with code 0
  - Test: Running `./suitey.sh -h` exits with code 0
  - Test: Help text contains "Suitey" in output
  - Test: Help text contains usage information
  - Test: Help text contains available options
  - Test: Running `./suitey.sh` (no args) shows help text
  - Test: Help text includes version information (if available)
- [x] **Green**: Implement help text display in `suitey.sh` (via build system)
  - Add `--help` and `-h` option handling to main script
  - Display usage information
  - Exit with code 0
  - Source `src/environment.sh` for environment checks
- [x] **Refactor**: Improve help text formatting, add more details

**0.3.3 Basic Exit Codes**
*Define and use exit code constants (0=success, 1=tests failed, 2=suitey error) throughout the script.*
- [x] **Red**: Write tests for exit codes
  - Test: `./suitey.sh --help` exits with code 0
  - Test: `./suitey.sh -h` exits with code 0
  - Test: `./suitey.sh --invalid-option` exits with code 2 (invalid argument)
  - Test: Script handles errors gracefully
  - Test: Script exits with code 0 when showing help
- [x] **Green**: Implement exit code logic in main script
  - Define exit code constants (0=success, 1=tests failed, 2=suitey error)
  - Handle help options (exit 0)
  - Handle invalid options (exit 2)
- [x] **Refactor**: Ensure consistent exit code usage

**0.3.4 Script Structure and Environment Integration**
*Integrate environment validation checks into main script execution, running them before commands that need them.*
- [x] **Red**: Write tests for script structure
  - Test: Script sources `src/environment.sh` functions (bundled in)
  - Test: Script defines main function
  - Test: Script calls main function at end
  - Test: Script runs environment checks before main execution
  - Test: Script handles environment check failures gracefully
- [x] **Green**: Implement basic script structure in source files
  - Source environment validation functions (bundled by build)
  - Define `main()` function
  - Call `main "$@"` at end
  - Integrate environment checks
- [x] **Refactor**: Organize script layout, add comments, improve error handling

**0.3.5 Basic Script Running**
*Verify suitey.sh runs correctly end-to-end with proper help, version, and error handling.*
- [x] **Red**: Write integration test `tests/bats/integration/suitey_basic.bats`
  - Test: `./suitey.sh --help` runs successfully (exit code 0)
  - Test: `./suitey.sh -h` runs successfully (exit code 0)
  - Test: Script shows help text when run without arguments
  - Test: Script validates environment before execution
  - Test: Script respects filesystem isolation (only reads project, writes to `/tmp`)
- [x] **Green**: Ensure script runs correctly end-to-end
- [x] **Refactor**: Optimize script execution, improve user experience

**0.3.6 Directory Argument Handling**
*Accept directory path as argument (e.g., suitey.sh .) and validate it exists and is readable before execution.*
- [x] **Red**: Write tests for directory argument handling
  - Test: `./suitey.sh` (no args) shows help text
  - Test: `./suitey.sh .` accepts current directory as argument
  - Test: `./suitey.sh /path/to/dir` accepts absolute directory path
  - Test: `./suitey.sh ../other-project` accepts relative directory path
  - Test: `./suitey.sh --help` still shows help (options take precedence)
  - Test: `./suitey.sh --version` still shows version (options take precedence)
  - Test: `./suitey.sh nonexistent-dir` exits with error code 2
  - Test: `./suitey.sh /nonexistent/path` exits with error code 2
  - Test: Directory argument is validated (exists, is readable)
- [x] **Green**: Implement directory argument handling in main script
  - Parse directory argument (non-option argument)
  - Validate directory exists and is readable
  - Store directory path for future use (workflow execution)
  - Options (`--help`, `--version`) take precedence over directory argument
  - Show appropriate error messages for invalid directories
- [x] **Refactor**: Improve argument parsing, add directory normalization (resolve relative paths)

**Acceptance Criteria**:
- `suitey.sh` exists after build (created by `build.sh`)
- `suitey.sh` is executable
- Help text displays correctly for `--help` and `-h`
- Script exits with code 0 when showing help
- Script shows help when run without arguments
- Script accepts directory argument (e.g., `suitey.sh .` or `suitey.sh /path/to/dir`)
- Script validates directory argument (exists, readable)
- Script integrates with environment validation
- Script structure is organized and maintainable
- Script can be run successfully

---

## Phase 1: Foundation Layer (No Dependencies)

### 1.1 Data Access Functions (`src/data_access.sh`)

**Goal**: Pure Bash data manipulation utilities with no external dependencies.

#### TDD Steps:

**1.1.1 Basic Key-Value Access**
*Implement data_get() function to extract values from key=value format data strings.*
- [ ] **Red**: Write test `tests/bats/unit/data_access.bats` for `data_get()`
  - Test: Extract simple value from `key=value` format
  - Test: Return empty string for missing key
  - Test: Handle empty input (exit code 1)
- [ ] **Green**: Implement `data_get()` in `src/data_access.sh`
- [ ] **Refactor**: Optimize string parsing, add error handling

**1.1.2 Array Access**
*Implement functions to access array elements by index, get array count, and retrieve all array elements.*
- [ ] **Red**: Write tests for `data_get_array()`, `data_array_count()`, `data_get_array_all()`
  - Test: Extract array element by index
  - Test: Get array count
  - Test: Get all array elements
  - Test: Handle missing arrays (return empty/0)
- [ ] **Green**: Implement array access functions
- [ ] **Refactor**: Consolidate array logic, improve validation

**1.1.3 Data Modification**
*Implement functions to set key-value pairs, append to arrays, and replace entire arrays in data strings.*
- [ ] **Red**: Write tests for `data_set()`, `data_array_append()`, `data_set_array()`
  - Test: Set new key-value pair
  - Test: Update existing key-value pair
  - Test: Append to array
  - Test: Replace entire array
- [ ] **Green**: Implement data modification functions
- [ ] **Refactor**: Optimize string manipulation, handle edge cases

**1.1.4 Multi-line Support**
*Implement functions to store and retrieve multi-line values using heredoc syntax in data strings.*
- [ ] **Red**: Write tests for `data_set_multiline()`, `data_get_multiline()`
  - Test: Set multi-line value with heredoc syntax
  - Test: Get multi-line value (strip heredoc markers)
  - Test: Handle existing heredoc blocks (replace)
- [ ] **Green**: Implement multi-line support
- [ ] **Refactor**: Improve heredoc parsing, handle edge cases

**1.1.5 Data Validation**
*Implement functions to validate data format and check if keys exist in data strings.*
- [ ] **Red**: Write tests for `data_validate()`, `data_has_key()`
  - Test: Validate correct data format
  - Test: Reject invalid formats
  - Test: Check key existence
- [ ] **Green**: Implement validation functions
- [ ] **Refactor**: Optimize validation logic

**Acceptance Criteria**:
- All data access functions pass unit tests
- Functions handle edge cases (empty input, missing keys, invalid formats)
- No external dependencies (pure Bash)
- Functions documented with usage examples

---

### 1.2 Suitey Modules Registry

**Goal**: Centralized registry for Suitey Modules with registration, lookup, and lifecycle management.

#### TDD Steps:

**1.2.1 Module Registration**
*Implement register_module() to register Suitey modules with validation of required interface methods.*
- [ ] **Red**: Write test `tests/bats/unit/mod_registry.bats` for module registration
  - Test: Register a module successfully
  - Test: Reject module with duplicate identifier
  - Test: Reject module missing required interface methods
  - Test: Validate module metadata structure
- [ ] **Green**: Implement `register_module()` in `src/mod_registry.sh`
- [ ] **Refactor**: Improve validation logic, error messages

**1.2.2 Module Lookup**
*Implement functions to retrieve modules by identifier, get all modules, and filter by capability.*
- [ ] **Red**: Write tests for module retrieval
  - Test: Get module by identifier
  - Test: Get all registered modules
  - Test: Get modules by capability
  - Test: Handle missing module (error)
- [ ] **Green**: Implement `get_module()`, `get_all_modules()`, `get_modules_by_capability()`
- [ ] **Refactor**: Optimize lookup performance, add caching

**1.2.3 Module Interface Validation**
*Verify that registered modules implement all required methods with correct signatures.*
- [ ] **Red**: Write tests for interface compliance checking
  - Test: Verify module implements all required methods
  - Test: Check method signatures match interface
  - Test: Validate return value formats
- [ ] **Green**: Implement interface validation logic
- [ ] **Refactor**: Improve validation coverage

**1.2.4 Minimal Module Implementation (Rust)**
*Create mod/languages/rust/mod.sh with stub implementations of detect() and get_metadata() methods.*
- [ ] **Red**: Write test for Rust module stub
  - Test: Module can be registered
  - Test: Module implements `detect()` method (returns detection result)
  - Test: Module implements `get_metadata()` method
- [ ] **Green**: Create `mod/languages/rust/mod.sh` with stub implementations
- [ ] **Refactor**: Improve module structure, add documentation

**1.2.5 Minimal Module Implementation (Bash)**
*Create mod/languages/bash/mod.sh with stub implementations of detect() and get_metadata() methods.*
- [ ] **Red**: Write test for Bash module stub
  - Test: Module can be registered
  - Test: Module implements `detect()` method
  - Test: Module implements `get_metadata()` method
- [ ] **Green**: Create `mod/languages/bash/mod.sh` with stub implementations
- [ ] **Refactor**: Ensure consistent module structure

**Acceptance Criteria**:
- Registry can register and retrieve modules
- Interface validation works correctly
- At least two stub modules (Rust, Bash) can be registered
- All registry operations respect filesystem isolation (only `/tmp`)

---

## Phase 2: Detection Layer (Depends on Foundation)

### 2.1 Platform Detector

**Goal**: Identify which programming languages/frameworks are present in a project.

#### TDD Steps:

**2.1.1 Basic Detection**
*Implement detect_platforms() to identify programming languages/frameworks present in a project using module detection.*
- [ ] **Red**: Write test `tests/bats/unit/platform_detector.bats` for platform detection
  - Test: Detect Rust project (presence of `Cargo.toml`)
  - Test: Detect Bash/BATS project (presence of `.bats` files)
  - Test: Return empty list for project with no detected platforms
  - Test: Handle multiple platforms in same project
- [ ] **Green**: Implement `detect_platforms()` in `src/platform_detector.sh`
  - Use Modules Registry to get available modules
  - Call each module's `detect()` method
  - Aggregate results
- [ ] **Refactor**: Improve error handling, optimize detection order

**2.1.2 Binary Availability Checking**
*Verify that required binaries (e.g., cargo, bats) are available for detected platforms, skip with warning if missing.*
- [ ] **Red**: Write tests for binary checking
  - Test: Verify `cargo` is available for Rust projects
  - Test: Verify `bats` is available for BATS projects
  - Test: Handle missing binaries gracefully (skip platform with warning)
- [ ] **Green**: Implement binary checking using module's `check_binaries()` method
- [ ] **Refactor**: Improve binary detection, add version checking

**2.1.3 Detection Confidence Levels**
*Calculate confidence levels (high/medium/low) based on presence of config files, test files, and file extensions.*
- [ ] **Red**: Write tests for confidence levels
  - Test: High confidence when config file + test files present
  - Test: Medium confidence when only test files present
  - Test: Low confidence when only file extensions present
- [ ] **Green**: Implement confidence level calculation in modules
- [ ] **Refactor**: Refine confidence heuristics

**2.1.4 Integration with Modules Registry**
*Integrate Platform Detector with Modules Registry to use registered modules for platform detection.*
- [ ] **Red**: Write integration test
  - Test: Platform Detector uses Modules Registry to get modules
  - Test: Detection results include module metadata
  - Test: Handle registry errors gracefully
- [ ] **Green**: Integrate Platform Detector with Modules Registry
- [ ] **Refactor**: Improve integration, error handling

**Acceptance Criteria**:
- Can detect Rust and Bash/BATS projects
- Returns structured detection results (flat data format)
- Handles missing tools gracefully
- Respects filesystem isolation (read-only project access)

---

### 2.2 Test Suite Detector

**Goal**: Find and group test files into distinct test suites after platforms are detected.

#### TDD Steps:

**2.2.1 Basic Test File Discovery**
*Implement discover_test_suites() to find and list test files for detected platforms using module discovery methods.*
- [ ] **Red**: Write test `tests/bats/unit/test_suite_detector.bats` for test discovery
  - Test: Discover Rust unit tests in `src/` directory
  - Test: Discover Rust integration tests in `tests/` directory
  - Test: Discover BATS test files (`.bats` files)
  - Test: Return empty list when no tests found
- [ ] **Green**: Implement `discover_test_suites()` in `src/test_suite_detector.sh`
  - Use Modules Registry to get modules for detected platforms
  - Call each module's `discover_test_suites()` method
- [ ] **Refactor**: Improve discovery logic, handle edge cases

**2.2.2 Suite Grouping**
*Group discovered test files into distinct test suites (e.g., one suite per BATS file, unit vs integration for Rust).*
- [ ] **Red**: Write tests for suite grouping
  - Test: Group BATS files by file (one suite per file)
  - Test: Group Rust tests by type (unit vs integration)
  - Test: Handle multiple test suites per platform
- [ ] **Green**: Implement suite grouping logic
- [ ] **Refactor**: Improve grouping strategies

**2.2.3 Test Counting**
*Count individual tests in test files (e.g., @test annotations in BATS, #[test] functions in Rust) using module parsing.*
- [ ] **Red**: Write tests for test counting
  - Test: Count `@test` annotations in BATS files
  - Test: Count `#[test]` functions in Rust files
  - Test: Handle files with no tests
- [ ] **Green**: Implement test counting using module's parsing logic
- [ ] **Refactor**: Optimize counting, handle edge cases

**2.2.4 Integration with Platform Detector**
*Integrate Test Suite Detector with Platform Detector to only discover tests for detected platforms.*
- [ ] **Red**: Write integration test
  - Test: Test Suite Detector uses Platform Detector results
  - Test: Only detects tests for detected platforms
  - Test: Handles platform detection failures gracefully
- [ ] **Green**: Integrate Test Suite Detector with Platform Detector
- [ ] **Refactor**: Improve integration, error handling

**Acceptance Criteria**:
- Can discover test suites for Rust and BATS projects
- Groups tests into distinct suites correctly
- Counts individual tests accurately
- Returns structured results (flat data format)

---

### 2.3 Build System Detector

**Goal**: Determine if and how projects need to be built before testing.

#### TDD Steps:

**2.3.1 Build Requirement Detection**
*Implement detect_build_requirements() to determine if projects need building before testing using module detection.*
- [ ] **Red**: Write test `tests/bats/unit/build_system_detector.bats` for build detection
  - Test: Detect Rust requires build (`Cargo.toml` present)
  - Test: Detect BATS does not require build
  - Test: Detect Make-based builds (`Makefile` present)
  - Test: Return `requires_build=false` when no build needed
- [ ] **Green**: Implement `detect_build_requirements()` in `src/build_system_detector.sh`
  - Use Modules Registry to get modules
  - Call each module's `detect_build_requirements()` method
- [ ] **Refactor**: Improve detection logic

**2.3.2 Build Step Identification**
*Identify build commands (e.g., cargo build, make targets) required for each platform using module get_build_steps().*
- [ ] **Red**: Write tests for build step identification
  - Test: Identify `cargo build` for Rust projects
  - Test: Identify build commands from `Makefile`
  - Test: Return empty build steps when no build required
- [ ] **Green**: Implement build step identification using module's `get_build_steps()` method
- [ ] **Refactor**: Improve step identification

**2.3.3 Build Dependency Analysis**
*Analyze dependencies between build steps to determine execution order and identify parallelizable builds.*
- [ ] **Red**: Write tests for dependency analysis
  - Test: Identify build dependencies between frameworks
  - Test: Determine build execution order
  - Test: Handle independent builds (can run in parallel)
- [ ] **Green**: Implement dependency analysis
- [ ] **Refactor**: Optimize dependency resolution

**Acceptance Criteria**:
- Can detect build requirements for Rust and BATS projects
- Identifies build commands correctly
- Returns structured build requirements (flat data format)
- Respects filesystem isolation (read-only project access)

---

### 2.4 Project Scanner (Orchestrator)

**Goal**: Coordinate Platform Detection, Test Suite Detection, and Build System Detection.

#### TDD Steps:

**2.4.1 Orchestration Workflow**
*Implement scan_project() to coordinate Platform Detection, Test Suite Detection, and Build System Detection in order.*
- [ ] **Red**: Write test `tests/bats/unit/project_scanner.bats` for orchestration
  - Test: Calls Platform Detector first
  - Test: Calls Test Suite Detector after Platform Detection
  - Test: Calls Build System Detector after Platform Detection
  - Test: Aggregates results from all detectors
- [ ] **Green**: Implement `scan_project()` in `src/project_scanner.sh`
  - Orchestrate detection phases in correct order
  - Aggregate results
- [ ] **Refactor**: Improve orchestration logic, error handling

**2.4.2 Result Aggregation**
*Combine results from all detection phases (platforms, test suites, build requirements) into unified data structure.*
- [ ] **Red**: Write tests for result aggregation
  - Test: Combine platform detection results
  - Test: Combine test suite results
  - Test: Combine build requirement results
  - Test: Handle partial failures (some detectors fail)
- [ ] **Green**: Implement result aggregation
- [ ] **Refactor**: Improve aggregation logic

**2.4.3 Error Handling**
*Handle detection failures gracefully, continue with other detectors when one fails, and provide clear error messages.*
- [ ] **Red**: Write tests for error handling
  - Test: Handle Platform Detector failures gracefully
  - Test: Continue with other detectors when one fails
  - Test: Provide clear error messages
- [ ] **Green**: Implement error handling
- [ ] **Refactor**: Improve error messages, recovery

**2.4.4 End-to-End Integration Test**
*Verify complete scanning workflow detects platforms, discovers test suites, and identifies build requirements correctly.*
- [ ] **Red**: Write integration test for full scanning workflow
  - Test: Scan multi-platform project (Rust + BATS)
  - Test: Verify all platforms detected
  - Test: Verify all test suites discovered
  - Test: Verify build requirements identified
- [ ] **Green**: Ensure all components work together
- [ ] **Refactor**: Optimize end-to-end performance

**Acceptance Criteria**:
- Orchestrates detection phases in correct order (Platform → Test Suite → Build System)
- Aggregates results correctly
- Handles errors gracefully
- Respects filesystem isolation (read-only operations)

---

## Phase 3: Execution Layer (Depends on Detection)

### 3.1 Build Manager

**Goal**: Execute build steps in Docker containers and create test images.

#### TDD Steps:

**3.1.1 Docker Container Management**
*Implement container lifecycle management: launch build containers with correct mounts, track containers, and clean up on completion.*
- [ ] **Red**: Write test `tests/bats/unit/build_manager.bats` (with Docker mocking)
  - Test: Launch build container with correct configuration
  - Test: Mount project directory read-only
  - Test: Mount `/tmp` artifact directory read-write
  - Test: Clean up containers on completion
- [ ] **Green**: Implement container management in `src/build_manager.sh`
- [ ] **Refactor**: Improve container lifecycle management

**3.1.2 Build Execution**
*Execute build commands in Docker containers, capture output and exit codes, and track build duration.*
- [ ] **Red**: Write tests for build execution
  - Test: Execute build command in container
  - Test: Capture build output (stdout/stderr)
  - Test: Detect build failures (non-zero exit code)
  - Test: Track build duration
- [ ] **Green**: Implement build execution logic
- [ ] **Refactor**: Improve build monitoring, error handling

**3.1.3 Multi-Core Build Support**
*Allocate multiple CPU cores to build containers and use parallel build flags (e.g., -j$(nproc)) for faster builds.*
- [ ] **Red**: Write tests for multi-core support
  - Test: Allocate multiple CPU cores to build container
  - Test: Use parallel build flags (`-j$(nproc)`)
  - Test: Handle single-core systems gracefully
- [ ] **Green**: Implement multi-core allocation
- [ ] **Refactor**: Optimize core allocation strategy

**3.1.4 Test Image Creation**
*Generate Dockerfiles and build Docker images containing build artifacts, source code, and test suites for test execution.*
- [ ] **Red**: Write tests for test image creation
  - Test: Generate Dockerfile for test image
  - Test: Build Docker image with artifacts
  - Test: Verify image contains build artifacts
  - Test: Verify image contains source code
  - Test: Verify image contains test suites
- [ ] **Green**: Implement test image creation
- [ ] **Refactor**: Optimize Dockerfile generation, image building

**3.1.5 Parallel Build Execution**
*Run independent builds in parallel while waiting for dependent builds sequentially, handling failures gracefully.*
- [ ] **Red**: Write tests for parallel builds
  - Test: Run independent builds in parallel
  - Test: Wait for dependent builds sequentially
  - Test: Handle build failures in parallel builds
- [ ] **Green**: Implement parallel build execution
- [ ] **Refactor**: Improve parallel execution management

**3.1.6 Integration Test with Real Docker**
*Verify build manager works with real Docker: builds projects, creates test images, and verifies artifacts are present.*
- [ ] **Red**: Write integration test `tests/bats/integration/build_manager.bats`
  - Test: Build simple Rust project
  - Test: Create test image successfully
  - Test: Verify artifacts in test image
- [ ] **Green**: Ensure real Docker operations work
- [ ] **Refactor**: Optimize Docker operations

**Acceptance Criteria**:
- Can execute builds in Docker containers
- Creates test images with artifacts, source, and tests
- Supports parallel builds
- Respects filesystem isolation (only `/tmp` modified)

---

### 3.2 Execution System

**Goal**: Execute test suites in Docker containers using native test runners.

#### TDD Steps:

**3.2.1 Test Container Execution**
*Launch test containers with pre-built images, execute test commands, and capture test output and exit codes.*
- [ ] **Red**: Write test `tests/bats/unit/execution_system.bats` (with Docker mocking)
  - Test: Launch test container with pre-built image
  - Test: Execute test command in container
  - Test: Capture test output
  - Test: Capture exit code
- [ ] **Green**: Implement test execution in `src/execution_system.sh`
- [ ] **Refactor**: Improve container management

**3.2.2 Result Collection**
*Collect test results (exit codes, stdout/stderr, duration) from containers and write structured results to /tmp.*
- [ ] **Red**: Write tests for result collection
  - Test: Collect exit code from test container
  - Test: Collect test output (stdout/stderr)
  - Test: Calculate execution duration
  - Test: Write results to `/tmp` in structured format
- [ ] **Green**: Implement result collection
- [ ] **Refactor**: Optimize result storage

**3.2.3 Result Parsing**
*Parse test output to extract test counts and individual test results using module parse_test_results() methods.*
- [ ] **Red**: Write tests for result parsing
  - Test: Parse test counts from Rust output
  - Test: Parse test counts from BATS output
  - Test: Extract individual test results (if parseable)
  - Test: Handle unparseable output gracefully
- [ ] **Green**: Implement parsing using module's `parse_test_results()` method
- [ ] **Refactor**: Improve parsing accuracy

**3.2.4 Integration with Modules Registry**
*Use module execution and parsing methods from Modules Registry, handling missing modules gracefully.*
- [ ] **Red**: Write tests for module integration
  - Test: Use module's execution method
  - Test: Use module's parsing method
  - Test: Handle missing modules gracefully
- [ ] **Green**: Integrate with Modules Registry
- [ ] **Refactor**: Improve integration

**3.2.5 Integration Test with Real Docker**
*Verify execution system works with real Docker: executes Rust and BATS tests in containers and collects results correctly.*
- [ ] **Red**: Write integration test `tests/bats/integration/execution_system.bats`
  - Test: Execute Rust tests in container
  - Test: Execute BATS tests in container
  - Test: Verify results are collected correctly
- [ ] **Green**: Ensure real Docker operations work
- [ ] **Refactor**: Optimize execution performance

**Acceptance Criteria**:
- Can execute tests in Docker containers
- Collects structured results correctly
- Parses test output accurately
- Respects filesystem isolation (results in `/tmp`)

---

### 3.3 Parallel Execution Manager

**Goal**: Coordinate parallel execution of multiple test suites.

#### TDD Steps:

**3.3.1 Parallel Launch**
*Launch multiple test suites in parallel Docker containers, limiting parallelism by CPU core count and tracking all containers.*
- [ ] **Red**: Write test `tests/bats/unit/parallel_execution.bats`
  - Test: Launch multiple test suites in parallel
  - Test: Limit parallelism by CPU core count
  - Test: Track all running containers
- [ ] **Green**: Implement parallel launch in `src/parallel_execution.sh`
- [ ] **Refactor**: Improve parallel execution management

**3.3.2 Result Monitoring**
*Poll result files in /tmp as tests complete, update status in real-time, and handle test failures gracefully.*
- [ ] **Red**: Write tests for result monitoring
  - Test: Poll result files in `/tmp` as tests complete
  - Test: Update status as tests finish
  - Test: Handle test failures gracefully
- [ ] **Green**: Implement result monitoring
- [ ] **Refactor**: Optimize polling, reduce overhead

**3.3.3 Signal Handling**
*Handle SIGINT (Ctrl+C) gracefully: terminate containers on first signal, force kill on second signal, and clean up on exit.*
- [ ] **Red**: Write tests for signal handling
  - Test: Handle SIGINT (first Ctrl+C) gracefully
  - Test: Terminate all containers on SIGINT
  - Test: Handle second SIGINT (force kill)
  - Test: Clean up containers on exit
- [ ] **Green**: Implement signal handling
- [ ] **Refactor**: Improve cleanup logic

**3.3.4 Resource Management**
*Limit concurrent containers by CPU count, clean up containers after completion, and remove temporary files from /tmp.*
- [ ] **Red**: Write tests for resource management
  - Test: Limit concurrent containers by CPU count
  - Test: Clean up containers after completion
  - Test: Clean up temporary files in `/tmp`
- [ ] **Green**: Implement resource management
- [ ] **Refactor**: Optimize resource usage

**Acceptance Criteria**:
- Can execute multiple test suites in parallel
- Limits parallelism appropriately
- Handles signals gracefully
- Cleans up resources correctly

---

## Phase 4: Presentation Layer (Depends on Execution)

### 4.1 Verbose Formatter

**Goal**: Stream raw test output directly to stdout/stderr.

#### TDD Steps:

**4.1.1 Output Streaming**
*Stream raw test output to stdout/stderr with suite identification prefixes, buffering output by suite for readability.*
- [ ] **Red**: Write test `tests/bats/unit/verbose_formatter.bats`
  - Test: Stream test output with suite identification prefix
  - Test: Buffer output by suite for readability
  - Test: Output buffer every 100ms (fallback)
- [ ] **Green**: Implement verbose formatter in `src/verbose_formatter.sh`
- [ ] **Refactor**: Optimize buffering, improve readability

**4.1.2 Post-Completion Output**
*Output all tests in execution order after completion, displaying stack traces for failures and errors.*
- [ ] **Red**: Write tests for post-completion output
  - Test: Output all tests in execution order
  - Test: Display stack traces for failures
  - Test: Display stack traces for errors
- [ ] **Green**: Implement post-completion output
- [ ] **Refactor**: Improve output formatting

**Acceptance Criteria**:
- Streams test output in real-time
- Includes suite identification
- Outputs final test summary with stack traces

---

### 4.2 Dashboard Formatter

**Goal**: Display real-time dashboard view of test execution.

#### TDD Steps:

**4.2.1 Dashboard Display**
*Display real-time dashboard with columns showing suite status, build status, and test counts that update as tests execute.*
- [ ] **Red**: Write test `tests/bats/unit/dashboard_formatter.bats`
  - Test: Display dashboard header with columns
  - Test: Update suite status in real-time
  - Test: Display build status when builds in progress
  - Test: Update test counts as tests complete
- [ ] **Green**: Implement dashboard formatter in `src/dashboard_formatter.sh`
- [ ] **Refactor**: Improve display formatting, optimize updates

**4.2.2 Real-Time Updates**
*Poll /tmp for result files, update dashboard when new results are available, and refresh display without flickering.*
- [ ] **Red**: Write tests for real-time updates
  - Test: Poll `/tmp` for result files
  - Test: Update dashboard when new results available
  - Test: Refresh display without flickering
- [ ] **Green**: Implement real-time update logic
- [ ] **Refactor**: Optimize polling frequency, reduce CPU usage

**4.2.3 Final Summary**
*Display overall test results, build results (if builds executed), and link to HTML report after all tests complete.*
- [ ] **Red**: Write tests for final summary
  - Test: Display overall test results
  - Test: Display build results (if builds executed)
  - Test: Display link to HTML report
- [ ] **Green**: Implement final summary
- [ ] **Refactor**: Improve summary formatting

**Acceptance Criteria**:
- Displays real-time dashboard
- Updates as tests execute
- Shows final summary with report link

---

### 4.3 Report Generation

**Goal**: Generate comprehensive HTML reports and serve them via Docker.

#### TDD Steps:

**4.3.1 HTML Report Generation**
*Generate comprehensive HTML reports from test results including summary statistics, detailed results, and build information.*
- [ ] **Red**: Write test `tests/bats/unit/report_generation.bats`
  - Test: Generate HTML report from test results
  - Test: Include summary statistics
  - Test: Include detailed test results
  - Test: Include build information (if builds executed)
  - Test: Save report to `/tmp/suitey-reports/`
- [ ] **Green**: Implement report generation in `src/report_generation.sh`
- [ ] **Refactor**: Improve HTML structure, styling

**4.3.2 Report Hosting**
*Launch nginx container with report directory mounted, serve reports on localhost:8080, and handle port conflicts automatically.*
- [ ] **Red**: Write tests for report hosting
  - Test: Launch nginx container with report directory mounted
  - Test: Serve report on localhost:8080
  - Test: Handle port conflicts (select next available port)
  - Test: Display clickable link in terminal
- [ ] **Green**: Implement report hosting
- [ ] **Refactor**: Improve container management

**4.3.3 Report Container Lifecycle**
*Manage report container lifecycle: runs until user stops it, cleans up on SIGINT, and tracks container ID for cleanup.*
- [ ] **Red**: Write tests for container lifecycle
  - Test: Container runs until user stops it
  - Test: Clean up container on SIGINT
  - Test: Track container ID for cleanup
- [ ] **Green**: Implement container lifecycle management
- [ ] **Refactor**: Improve cleanup logic

**Acceptance Criteria**:
- Generates comprehensive HTML reports
- Serves reports via Docker container
- Reports saved to `/tmp/suitey-reports/`
- Container lifecycle managed correctly

---

## Phase 5: Main Entry Point and Integration

### 5.1 Main Entry Point (`suitey`)

**Goal**: Command-line interface that orchestrates all components.

#### TDD Steps:

**5.1.1 Command-Line Interface**
*Add additional CLI options (--suite, --verbose) to suitey.sh, working with directory argument from Phase 0.3.6.*
- [ ] **Red**: Write test `tests/bats/integration/suitey_cli.bats`
  - Test: Parse command-line arguments (basic directory handling done in Phase 0.3.6)
  - Test: Handle `--suite` option
  - Test: Handle `--verbose` option
  - Test: Handle invalid arguments (exit code 2)
  - Test: Options work correctly with directory argument (e.g., `suitey.sh . --verbose`)
- [ ] **Green**: Implement additional CLI options in `src/suitey.sh`
  - Note: Basic directory argument handling is already implemented in Phase 0.3.6
- [ ] **Refactor**: Improve argument parsing, help text

**5.1.2 Workflow Orchestration**
*Orchestrate complete workflow: initialize, scan project, build (if needed), execute tests, display results, and generate report.*
- [ ] **Red**: Write integration test for full workflow
  - Test: Run `suitey.sh [DIRECTORY]` on project directory (directory argument from Phase 0.3.6)
  - Test: Execute complete workflow (init → discovery → build → execution)
  - Test: Display results correctly
  - Test: Generate report
- [ ] **Green**: Implement workflow orchestration
- [ ] **Refactor**: Improve error handling, user experience

**5.1.3 Exit Codes**
*Implement exit code logic: 0 when all tests pass, 1 when tests fail, 2 when suitey error occurs.*
- [ ] **Red**: Write tests for exit codes
  - Test: Exit code 0 when all tests pass
  - Test: Exit code 1 when tests fail
  - Test: Exit code 2 when suitey error occurs
- [ ] **Green**: Implement exit code logic
- [ ] **Refactor**: Ensure consistent exit code usage

**Acceptance Criteria**:
- Command-line interface works correctly
- Executes complete workflow
- Returns correct exit codes
- Respects filesystem isolation

---

## Testing Strategy

### Unit Tests
- Each component has comprehensive unit tests in `tests/bats/unit/`
- Use mocking for external dependencies (Docker, file system)
- Test edge cases and error conditions
- Aim for high code coverage

### Integration Tests
- Test component interactions in `tests/bats/integration/`
- Use real Docker for integration tests
- Test end-to-end workflows
- Verify filesystem isolation

### Test Execution
- Run unit tests: `bats tests/bats/unit/`
- Run integration tests: `bats tests/bats/integration/`
- Run all tests: `bats tests/bats/`
- Run tests in parallel: `bats -j $(nproc) tests/bats/unit/`

## Implementation Notes

1. **Filesystem Isolation**: All components must only modify `/tmp`. Project directories are read-only.

2. **Data Format**: All component communication uses the flat data format specified in `DATA-CONVENTIONS.md`.

3. **Error Handling**: Components should handle errors gracefully, provide clear messages, and continue when possible.

4. **Docker Operations**: Use Docker containers for all builds and test execution. Clean up containers and images appropriately.

5. **Parallel Execution**: Limit parallelism based on CPU core count. Balance speed with resource usage.

6. **Testing**: Follow TDD strictly. Write tests first, implement minimal code, refactor. Keep tests green.

## Success Criteria

- All phases implemented following TDD methodology
- All unit tests pass
- All integration tests pass
- Components respect filesystem isolation
- End-to-end workflow works correctly
- Documentation complete

