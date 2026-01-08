# Platform Detector Specification

## Overview

The Platform Detector is a specialized component of Suitey responsible for automatically identifying which languages and test frameworks are present and available in a project directory. It is called by Project Scanner as the **first phase** of the execution workflow. Platform Detector operates through module-based detection logic, where each Suitey Module implements language-specific heuristics. The Platform Detector works in conjunction with the Suitey Modules Registry to coordinate language-specific detection across multiple programming languages and frameworks. Its results inform subsequent phases: Test Suite Detection and Build System Detection.

## Responsibilities

The Platform Detector is responsible for:

1. **Language Identification**: Determining which programming languages are present in the project
2. **Module Coordination**: Working with the Suitey Modules Registry to execute language-specific detection logic
3. **Binary Availability Checking**: Verifying that required language tools are available
4. **Detection Result Aggregation**: Collecting and organizing detection results from all modules
5. **Language Metadata Collection**: Gathering information about detected languages and frameworks for downstream use
6. **Filesystem Read-Only Access**: Only reads from the project directory without modifying the host filesystem

## Architecture Position

The Platform Detector operates as part of the main suitey process:

```
┌─────────────────────────────────────┐
│         suitey (main process)       │
├─────────────────────────────────────┤
│  Project Scanner (Orchestrator)     │
│  ├─ Platform Detector              │ ← This component
│  │  └─ Suitey Modules Registry     │
│  ├─ Test Suite Detector             │
│  └─ Build System Detector           │
│  ...                                │
└─────────────────────────────────────┘
```

### Relationship to Other Components

- **Project Scanner**: The Project Scanner orchestrates overall project analysis and calls the Platform Detector as the **first step** in the workflow. Platform Detector's results inform subsequent phases (Test Suite Detection and Build System Detection).
- **Suitey Modules Registry**: The Platform Detector uses the Suitey Modules Registry to access language-specific detection logic. Each module implements detection methods that Platform Detector coordinates.
- **Test Suite Detector**: Platform detection results are used by Test Suite Detector to determine which modules to use for finding test files. Test Suite Detector operates **after** Platform Detection completes.
- **Build System Detector**: Platform detection results may inform build system detection, as some platforms require specific build steps. Build System Detector operates **after** Platform Detection completes.

## Detection Strategy

The Platform Detector uses a multi-layered approach to identify platforms:

### 1. Module-Based Detection

The primary detection mechanism uses Suitey Modules registered in the Suitey Modules Registry. Each module implements language-specific detection logic:

- **Detection Logic**: How to determine if this framework is present
- **Heuristic Application**: Framework-specific heuristics (file patterns, config files, directory structures)
- **Confidence Levels**: High, medium, low confidence in detection results
- **Binary Verification**: Checking for required framework tools

### 2. Detection Workflow

For each registered module, the Platform Detector:

1. **Retrieves Module**: Gets the Suitey Module from the Suitey Modules Registry
2. **Calls Detection Method**: Executes the module's `detect()` method
3. **Processes Results**: Handles detection results and confidence levels
4. **Binary Checking**: Verifies required tools are available
5. **Metadata Collection**: Gathers language information from the module
6. **Result Recording**: Records successful detections with metadata

### 3. Detection Confidence Levels

Platform detection uses confidence levels to handle ambiguous or weak detection results:

- **High Confidence**: Strong indicators present (e.g., framework config file + test files)
- **Medium Confidence**: Some indicators present (e.g., test files without config)
- **Low Confidence**: Weak indicators only (e.g., file extensions only)

### 4. Binary Availability Verification

For each detected platform, the detector verifies that required tools are available:

- **Required Binaries**: Framework executables (e.g., `bats`, `cargo`)
- **Path Resolution**: Finding tools in system PATH
- **Version Checking**: Verifying tool versions meet requirements
- **Installation Guidance**: Providing installation instructions when tools are missing

### 5. Language Metadata Collection

For each detected language, the detector collects:

- **Language Information**: Language name, supported frameworks
- **Project Type**: Type of projects this language supports
- **Capabilities**: Language capabilities (testing, compilation, etc.)
- **Required Binaries**: Tools needed for the language
- **Configuration Files**: Language configuration file patterns
- **Test Frameworks**: Available test frameworks for this language

## Supported Languages

The Platform Detector supports detection of the following programming languages:

### Rust
- Language: Rust
- Frameworks: Cargo (testing, compilation)
- Project Types: Cargo workspaces, binary projects

### Bash/Shell
- Language: Bash
- Frameworks: BATS (testing)
- Project Types: Shell script projects

## Detection Results

The Platform Detector produces:

1. **Detected Platforms**: List of platforms found in the project
   - Framework identifier/name
   - Detection confidence level
   - Framework version (if detectable)
   - Detection method used

2. **Framework Metadata**: Additional information about each detected framework
   - Required tools/binaries
   - Configuration file locations
   - Test file patterns
   - Build requirements
   - Execution capabilities

3. **Binary Availability Status**: For each detected framework
   - Required binaries found
   - Required binaries missing
   - Binary versions (if detectable)

4. **Detection Warnings**: Issues encountered during detection
   - Framework detected but tools unavailable
   - Multiple versions of same framework detected
   - Conflicting framework configurations
   - Ambiguous detection results

5. **Detection Errors**: Critical issues preventing platform detection
   - Invalid configuration files
   - Corrupted project structure
   - Unreadable files or directories

## Integration with Suitey Modules System

The Platform Detector works in conjunction with the Suitey Modules System:

1. **Module Access**: Retrieves registered modules from the Suitey Modules Registry
2. **Detection Delegation**: Delegates language-specific detection to each module
3. **Result Aggregation**: Collects and organizes results from all modules
4. **Metadata Collection**: Gathers language metadata from modules

### Module Interface Usage

The Platform Detector uses these module methods:

- **`detect(project_root)`**: Detects if language/framework is present, returns detection results
- **`check_binaries(project_root)`**: Verifies required tools are available
- **`get_metadata()`**: Returns language metadata for downstream use

## Error Handling

### Detection Errors

The Platform Detector handles various error conditions:

1. **Module Not Available**: Suitey Module not registered in Suitey Modules Registry
2. **Detection Method Failure**: Module's detect method fails or returns invalid results
3. **Binary Check Failure**: Unable to verify tool availability
4. **Metadata Retrieval Failure**: Unable to get framework metadata
5. **Conflicting Results**: Multiple modules detect the same platform
6. **Invalid Detection Results**: Malformed or incomplete detection data

### Error Recovery

When detection errors occur:

1. **Graceful Degradation**: Skip problematic frameworks, continue with others
2. **Warning Generation**: Generate warnings for detection issues
3. **Fallback Behavior**: Use default assumptions when possible
4. **Error Reporting**: Provide clear error messages to users

## Performance Considerations

### Efficient Detection

The Platform Detector optimizes detection performance:

1. **Parallel Detection**: Run multiple module detections concurrently
2. **Early Termination**: Stop detection when high-confidence result found
3. **Caching**: Cache detection results for repeated scans
4. **Selective Scanning**: Only scan relevant directories and files
5. **Resource Limits**: Limit concurrent detections to prevent resource exhaustion

### Scalability

The detector scales with project size:

1. **Incremental Scanning**: Scan project incrementally to avoid large upfront costs
2. **Priority-Based Detection**: Detect high-confidence frameworks first
3. **Lazy Evaluation**: Defer expensive checks until needed
4. **Memory Efficiency**: Process detection results in streaming fashion

## Implementation Notes

### Detection Algorithm

The Platform Detector implements a systematic detection algorithm:

1. **Module Retrieval**: Get all registered Suitey Modules
2. **Parallel Execution**: Execute detection methods concurrently
3. **Result Collection**: Gather detection results from all modules
4. **Conflict Resolution**: Handle multiple detections of same framework
5. **Validation**: Validate detection results and confidence levels
6. **Metadata Aggregation**: Collect metadata from successful detections
7. **Binary Verification**: Check tool availability for detected frameworks
8. **Result Formatting**: Format results for downstream consumption

### Cross-Platform Compatibility

The detector handles cross-platform concerns:

1. **Path Handling**: Platform-appropriate path separators and resolution
2. **Binary Location**: Finding tools in platform-specific locations
3. **File Permissions**: Handling permission differences across platforms
4. **Encoding**: Dealing with different file encodings and locales

### Extensibility

The Platform Detector is designed for extensibility:

1. **New Platform Support**: Easy addition of new Suitey Modules
2. **Custom Detection Logic**: Framework-specific detection algorithms
3. **Detection Strategies**: Different detection approaches for different scenarios
4. **Result Processing**: Custom processing of detection results

## Output Format

The Platform Detector outputs detection results in a structured format that includes:

- **Detected Frameworks List**: Frameworks found with confidence levels
- **Framework Metadata**: Detailed information about each framework
- **Binary Status**: Tool availability for each framework
- **Detection Warnings**: Non-critical issues encountered
- **Detection Errors**: Critical problems preventing detection

This structured output informs subsequent components about which frameworks are available and their capabilities, enabling appropriate test discovery and execution strategies.
