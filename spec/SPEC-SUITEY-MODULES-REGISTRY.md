# Suitey Modules Registry Specification

## Overview

The Suitey Modules Registry is a shared component of Suitey responsible for maintaining a centralized registry of Suitey Modules and providing a consistent interface for language-specific operations. It serves as the foundation for Suitey's language-agnostic architecture, enabling automatic detection, discovery, build detection, and execution of tests across multiple programming languages and frameworks without hardcoding specific logic. The Suitey Modules Registry is used by Platform Detector, Test Suite Detector, Build System Detector, and the execution system to coordinate module-based operations.

## Module Directory Structure

Suitey Modules are organized in a directory-based structure for easy development and distribution:

```
/mod/{type}/{name}/
├── mod.sh              # Main module implementation
├── tests/              # BATS test suite
│   └── *.bats
├── README.md           # Module documentation
├── metadata.sh         # Module metadata (optional)
└── [other files]       # Configs, assets, examples as needed
```

**Directory Components:**
- **`{type}`**: Module category (e.g., `languages`, `frameworks`, `projects`)
- **`{name}`**: Module identifier (e.g., `rust`, `cargo`, `my-project`)
- **`mod.sh`**: Core module implementation with interface methods
- **`tests/`**: Complete test suite for the module
- **`README.md`**: Documentation, usage, examples

## Module Types

Suitey Modules are organized into three distinct types, each serving a specific purpose in the detection and execution workflow:

### 1. Language Modules (`/mod/languages/{name}/`)

Language modules handle **language-level detection and operations**. They identify which programming languages are present in a project and provide language-specific capabilities.

**Examples:**
- `mod/languages/rust/mod.sh` - Detects Rust language presence
- `mod/languages/python/mod.sh` - Detects Python language presence
- `mod/languages/bash/mod.sh` - Detects Bash/Shell language presence

**Responsibilities:**
- Detect if a programming language is present in the project
- Identify language-specific indicators (file extensions, config files, etc.)
- Provide language-level metadata (language name, supported frameworks, capabilities)
- Check for language-specific binaries and tools

**Detection Priority:** Language modules are typically checked first during platform detection.

### 2. Framework Modules (`/mod/frameworks/{name}/`)

Framework modules handle **framework-specific operations** for test discovery, execution, and parsing. They work in conjunction with language modules to provide framework-specific behavior.

**Examples:**
- `mod/frameworks/cargo/mod.sh` - Handles Cargo framework (Rust)
- `mod/frameworks/pytest/mod.sh` - Handles pytest framework (Python)
- `mod/frameworks/bats/mod.sh` - Handles BATS framework (Bash)
- `mod/frameworks/jest/mod.sh` - Handles Jest framework (JavaScript)

**Responsibilities:**
- Discover test suites using framework-specific patterns
- Execute tests using framework-specific test runners
- Parse framework-specific test output
- Detect framework-specific build requirements
- Provide framework-specific build steps

**Relationship to Language Modules:** Framework modules are selected based on detected languages. A language module may indicate which frameworks it supports, and framework modules provide the actual implementation for those frameworks.

### 3. Project Modules (`/mod/projects/{name}/`)

Project modules handle **project-specific configurations and customizations**. They allow individual projects to override or extend default behavior for their specific needs.

**Examples:**
- `mod/projects/my-company-standard/mod.sh` - Company-wide testing standards
- `mod/projects/legacy-system/mod.sh` - Custom behavior for legacy projects
- `mod/projects/microservices/mod.sh` - Microservices-specific test patterns

**Responsibilities:**
- Override default detection behavior for specific projects
- Customize test discovery patterns
- Modify build steps for project-specific requirements
- Provide project-specific execution configurations
- Handle project-specific edge cases

**Priority:** Project modules have the highest priority and can override language and framework module behavior when present. They are typically detected last and take precedence.

### Module Interaction and Priority

Modules interact in a hierarchical manner:

1. **Language Detection**: Language modules detect which languages are present
2. **Framework Selection**: Framework modules are selected based on detected languages
3. **Project Customization**: Project modules override or extend behavior as needed

**Priority Order (highest to lowest):**
1. Project modules (highest priority - can override everything)
2. Framework modules (provide framework-specific behavior)
3. Language modules (provide language-level detection)

**Example Workflow:**
1. Language module (`rust`) detects Rust is present
2. Framework module (`cargo`) handles Cargo-specific test discovery and execution
3. Project module (`my-project`) may override specific behaviors for this project

## Responsibilities

The Suitey Modules Registry is responsible for:

1. **Module Registration**: Maintaining a registry of all available Suitey Modules
2. **Module Access**: Providing access to registered modules for language-specific operations
3. **Interface Enforcement**: Ensuring all modules implement the required interface
4. **Module Lifecycle Management**: Managing module initialization, validation, and cleanup
5. **Module Discovery**: Enabling discovery of available modules at runtime
6. **Metadata Management**: Storing and providing access to module metadata (language, frameworks, capabilities, etc.)
7. **Error Handling**: Managing module-related errors and providing graceful degradation
8. **Filesystem Isolation**: Registry operations do not modify the host filesystem except for `/tmp` when necessary

## Architecture Position

The Suitey Modules Registry operates as a shared component within the main suitey process.

### Relationship to Other Components

- **Platform Detector**: Uses the Suitey Modules Registry to access language-specific detection logic. Platform Detector coordinates module-based detection by calling detection methods on registered modules.
- **Test Suite Detector**: Uses the Suitey Modules Registry to access language-specific detection logic. Test Suite Detector uses modules to find test files using language-specific patterns.
- **Build System Detector**: Uses the Suitey Modules Registry to access language-specific build detection logic. Build System Detector uses modules to determine build requirements per language.
- **Execution System**: Uses the Suitey Modules Registry to access language-specific execution and parsing logic. The execution system uses modules to run tests and extract structured results.
- **Project Scanner**: Orchestrates components that use the Suitey Modules Registry, but does not directly access it.

## Suitey Module Interface

All Suitey Modules must implement a consistent interface that defines the contract for language-specific operations. The interface consists of the following methods:

### Core Interface Methods

#### 1. Detection Methods

- **`detect(project_root: string) -> DetectionResult`**
  - Determines if this language/framework is present in the project
  - Uses language-specific heuristics (config files, package manager files, directory patterns, etc.)
  - Returns detection results as flat data:
    - `detected=true/false` - Whether the language/framework is present
    - `confidence=high/medium/low` - Confidence level
    - `indicators_0=...` - List of indicators that led to detection
    - `indicators_1=...`
    - `indicators_count=N`
    - `language=rust/bash/etc` - Detected language
    - `frameworks_0=cargo/bats/etc` - Supported frameworks for this language

- **`check_container_environment(project_root: string) -> ContainerStatus`**
  - Verifies that the container environment is ready for test execution
  - Checks Docker daemon accessibility and basic container operations
  - Returns container environment status as flat data:
    - `docker_available=true/false` - Whether Docker daemon is accessible
    - `container_operations=true/false` - Whether basic container operations work
    - `network_access=true/false` - Whether network connectivity allows image pulls
    - `base_images_available=true/false` - Whether required base images are accessible
    - `container_check=true` - Always checks container environment (not host binaries)

#### 2. Discovery Methods

- **`discover_test_suites(project_root: string, framework_metadata: object) -> TestSuite[]`**
  - Finds test files/suites for this framework using framework-specific patterns
  - Uses framework-specific heuristics (directory patterns, file naming conventions, etc.)
  - Returns test suites as flat data:
    - `suites_count=N` - Number of test suites
    - `suites_0_name=...` - Suite identifier/name
    - `suites_0_framework=...` - Framework identifier
    - `suites_0_test_files_0=...` - List of test file paths
    - `suites_0_test_files_1=...`
    - `suites_0_test_files_count=N`
    - `suites_0_metadata_count=0` - Suite-specific metadata
    - `suites_0_execution_config_count=0` - Execution configuration

#### 3. Build Detection Methods

- **`detect_build_requirements(project_root: string, framework_metadata: object) -> BuildRequirements`**
  - Determines if building is required before testing
  - Analyzes build configuration files, package manager scripts, source code patterns
  - Returns build requirements as flat data:
    - `requires_build=true/false` - Whether building is required
    - `build_steps_count=N` - List of build steps needed
    - `build_commands_0=...` - Specific build commands
    - `build_commands_1=...`
    - `build_commands_count=N`
    - `build_dependencies_0=...` - Build dependencies
    - `build_dependencies_1=...`
    - `build_dependencies_count=N`
    - `build_artifacts_0=...` - Expected build artifacts
    - `build_artifacts_1=...`
    - `build_artifacts_count=N`

- **`get_build_steps(project_root: string, build_requirements: BuildRequirements) -> BuildStep[]`**
  - Specifies how to build the project in a containerized environment
  - Returns build steps as flat data:
    - `build_steps_count=N` - Number of build steps
    - `build_steps_0_step_name=...` - Build step identifier
    - `build_steps_0_docker_image=...` - Docker base image to use for building
    - `build_steps_0_install_dependencies_command=...` - Command to install dependencies (optional)
    - `build_steps_0_build_command=...` - Build command to execute (should support parallel builds)
    - `build_steps_0_working_directory=...` - Working directory in container
    - `build_steps_0_volume_mounts_count=N` - Volume mounts for build artifacts (temporary)
    - `build_steps_0_environment_variables_count=N` - Environment variables
    - `build_steps_0_cpu_cores=N` - Number of CPU cores to allocate (optional, defaults to available cores)

#### 4. Execution Methods

- **`execute_test_suite(test_suite: TestSuite, test_image: TestImage, execution_config: object) -> ExecutionResult`**
  - Runs tests using the framework's native tools in containers
  - Uses pre-built test image (if build was required) or base image (if no build)
  - Handles Docker container creation, execution, and cleanup
  - Returns execution results as flat data:
    - `exit_code=N` - Exit code from test runner
    - `duration=N.N` - Execution time in seconds
    - `output=...` - Raw stdout/stderr output (may use heredoc)
    - `container_id=...` - Docker container ID (if used)
    - `execution_method=docker` - Execution method used
    - `test_image=...` - Test image name/tag used (if applicable)

#### 5. Parsing Methods

- **`parse_test_results(output: string, exit_code: number) -> ParsedResults`**
  - Extracts test results (counts, status, output) from framework output
  - Parses framework-specific output patterns
  - Returns parsed results as flat data:
    - `total_tests=N` - Total number of tests
    - `passed_tests=N` - Number of passed tests
    - `failed_tests=N` - Number of failed tests
    - `skipped_tests=N` - Number of skipped tests (if applicable)
    - `test_details_0=...` - Individual test results (if parseable)
    - `test_details_1=...`
    - `test_details_count=N`
    - `status=passed/failed/error` - Overall status

#### 6. Metadata Methods

- **`get_metadata() -> SuiteyModuleMetadata`**
  - Returns Suitey Module metadata
  - Returns module metadata as flat data:
    - `module_type=language/framework/project` - Type of module (required)
    - `language=...` - Programming language this module handles (for language/framework modules)
    - `frameworks_0=...` - Supported frameworks (for language modules) or framework name (for framework modules)
    - `frameworks_1=...`
    - `frameworks_count=N`
    - `project_type=...` - Type of projects this module handles
    - `version=...` - Module version
    - `capabilities_0=...` - Module capabilities
    - `capabilities_1=...`
    - `capabilities_count=N`
    - `required_binaries_0=...` - Required binaries
    - `required_binaries_1=...`
    - `required_binaries_count=N`
    - `priority=N` - Module priority (higher = more precedence, defaults to 0 for language, 1 for framework, 2 for project)

### Interface Compliance

- All modules must implement all interface methods
- Methods may return empty/null values when not applicable (e.g., `requires_build=false` when no build is needed)
- Methods should handle errors gracefully and return appropriate error indicators
- Modules should validate inputs and provide clear error messages

## Registration System

The Suitey Modules Registry maintains a registry of all available Suitey Modules. Modules can be registered in several ways:

### 1. Built-in Modules

Built-in modules are registered automatically when the Suitey Modules Registry is initialized. These include:

**Language Modules:**
- **Rust Language Module** (`mod/languages/rust/mod.sh`) - Detects Rust language presence
- **Bash Language Module** (`mod/languages/bash/mod.sh`) - Detects Bash/Shell language presence

**Framework Modules:**
- Framework modules are typically registered when their corresponding language is detected, or can be registered independently
- Examples: Cargo (Rust), BATS (Bash), pytest (Python), Jest (JavaScript)

**Project Modules:**
- Project modules are optional and are typically discovered in the project directory itself
- They can be placed in the project root (e.g., `.suitey/mod/projects/{name}/mod.sh`) or in the Suitey installation

### 2. Registration Process

1. **Module Initialization**: Module is instantiated and validated
2. **Interface Validation**: Registry verifies module implements required interface
3. **Metadata Extraction**: Registry extracts module metadata
4. **Registration**: Module is added to registry with unique identifier
5. **Capability Registration**: Module capabilities are registered

### 3. Module Identifiers

Each module has a unique identifier used for:
- Registry lookup
- Language identification
- Error reporting
- Logging

Identifiers should be:
- Lowercase
- Hyphen-separated (e.g., `rust-module`, `bash-module`)
- Descriptive and language-specific

### 4. Registration API

The registry provides methods for module registration:

- **`register_module(module: SuiteyModule) -> void`**
  - Registers a new module
  - Validates interface compliance
  - Throws error if module is invalid or identifier conflicts

- **`unregister_module(identifier: string) -> void`**
  - Removes a module from the registry
  - Cleans up associated resources

### 5. Registration Validation

The registry validates modules during registration:

1. **Interface Compliance**: Verifies all required methods are implemented
2. **Metadata Validity**: Validates module metadata structure
3. **Identifier Uniqueness**: Ensures identifier is not already registered
4. **Capability Validation**: Validates declared capabilities

## Module Lookup System

The registry provides methods to access registered modules:

### 1. Module Retrieval

- **`get_module(identifier: string) -> SuiteyModule`**
  - Returns module by identifier
  - Throws error if module not found

- **`get_all_modules() -> SuiteyModule[]`**
  - Returns all registered modules
  - Returns list of module identifiers

### 2. Capability-Based Lookup

- **`get_modules_by_capability(capability: string) -> SuiteyModule[]`**
  - Returns modules that support a specific capability
  - Used by components to find suitable modules

- **`get_capabilities() -> string[]`**
  - Returns all registered capabilities
  - Used for capability enumeration

### 3. Type-Based Lookup

- **`get_modules_by_type(module_type: string) -> SuiteyModule[]`**
  - Returns modules of a specific type (`language`, `framework`, or `project`)
  - Used to filter modules by their category
  - Example: `get_modules_by_type("language")` returns all language modules

- **`get_language_modules() -> SuiteyModule[]`**
  - Returns modules that can detect languages (convenience method for `get_modules_by_type("language")`)
  - Used by Platform Detector

- **`get_framework_modules() -> SuiteyModule[]`**
  - Returns all framework modules (convenience method for `get_modules_by_type("framework")`)
  - Used by Test Suite Detector and Execution System

- **`get_project_modules() -> SuiteyModule[]`**
  - Returns all project modules (convenience method for `get_modules_by_type("project")`)
  - Used to check for project-specific customizations

### 4. Metadata Access

- **`get_module_metadata(identifier: string) -> SuiteyModuleMetadata`**
  - Returns module metadata by identifier
  - Used for module introspection

## Error Handling

### Registration Errors

The registry handles registration-related errors:

1. **Invalid Module**: Module doesn't implement required interface
2. **Duplicate Identifier**: Module identifier already exists
3. **Invalid Metadata**: Module metadata is malformed
4. **Capability Conflict**: Declared capabilities are invalid

### Lookup Errors

The registry handles lookup-related errors:

1. **Module Not Found**: Requested module doesn't exist
2. **Capability Not Supported**: No modules support requested capability
3. **Metadata Not Available**: Module metadata cannot be retrieved

### Error Recovery

When errors occur:

1. **Graceful Degradation**: Continue with available modules when possible
2. **Error Logging**: Log errors with appropriate detail level
3. **User Notification**: Provide clear error messages to users
4. **Fallback Behavior**: Use default modules when available

## Implementation Details

### Storage Mechanism

The registry uses internal data structures to store module information:

1. **Module Map**: Maps module identifiers to module instances
2. **Metadata Cache**: Caches module metadata for quick access
3. **Capability Index**: Maps capabilities to module lists
4. **Registration Order**: Maintains module registration order

### Thread Safety

The registry ensures thread-safe operations:

1. **Concurrent Access**: Safe for concurrent reads during execution
2. **Registration Lock**: Prevents concurrent registration conflicts
3. **Immutable Metadata**: Metadata is immutable after registration

### Performance Considerations

The registry optimizes for performance:

1. **Lazy Loading**: Load modules only when needed
2. **Metadata Caching**: Cache frequently accessed metadata
3. **Fast Lookup**: O(1) module lookup by identifier
4. **Capability Indexing**: Fast capability-based queries

### Memory Management

The registry manages memory efficiently:

1. **Module Lifecycle**: Proper cleanup of module instances
2. **Cache Management**: Limit cache size and implement eviction
3. **Resource Cleanup**: Clean up resources on registry shutdown

## Integration Patterns

### Platform Detector Integration

The Platform Detector uses the registry to:

1. **Module Discovery**: Get all registered modules
2. **Detection Delegation**: Call detect methods on each module
3. **Result Aggregation**: Collect detection results
4. **Metadata Access**: Get platform metadata from modules

### Test Suite Detector Integration

Test Suite Detector uses the registry to:

1. **Platform Matching**: Find modules for detected platforms
2. **Detection Delegation**: Call detection methods on matched modules
3. **Result Processing**: Process detected test suites

### Build System Detector Integration

Build System Detector uses the registry to:

1. **Suitey Modules**: Get modules for build detection
2. **Build Requirements**: Call build detection methods
3. **Build Steps**: Get build execution specifications

### Execution System Integration

The execution system uses the registry to:

1. **Module Selection**: Select appropriate modules for test execution
2. **Execution Methods**: Call execution methods on modules
3. **Result Parsing**: Use modules to parse test results

## Extensibility

### Adding New Modules

To add a new Suitey Module:

1. **Implement Interface**: Create module implementing all interface methods
2. **Define Metadata**: Provide module metadata using flat naming conventions
3. **Register Module**: Register module with the registry
4. **Test Integration**: Verify module works with all components

### Custom Capabilities

Modules can declare custom capabilities:

1. **Capability Declaration**: Define capabilities in module metadata
2. **Capability Registration**: Registry indexes custom capabilities
3. **Capability Lookup**: Components can query by custom capabilities

### Module Extensions

The registry supports module extensions:

1. **Optional Methods**: Modules can implement additional methods
2. **Extension Registration**: Register extensions with the registry
3. **Extension Discovery**: Components can discover module extensions

## Future Considerations

- Dynamic module loading from external sources
- Module version management and compatibility
- Performance monitoring and optimization
- Module health checking and recovery
- Plugin system for third-party modules
- Module marketplace and discovery
- Cross-platform module compatibility
- Module testing and validation frameworks
