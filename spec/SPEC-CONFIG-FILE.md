# Suitey Configuration File Specification

## Overview

Suitey supports configuration files that allow users to explicitly define test suite organization, override automatic detection, and customize test execution behavior. Configuration files provide the highest priority in Suitey's adaptive detection strategy, allowing complete control over test suite grouping and execution.

## Goals

1. **Explicit Control**: Override automatic detection when needed
2. **Zero Dependencies**: Parsing uses standard tools (no external TOML/JSON parsers required)
3. **Human Readable**: Easy to write and maintain
4. **Flexible**: Support both simple and complex project structures
5. **Framework Agnostic**: Work across all supported languages and frameworks
6. **Backward Compatible**: Optional - projects work without configuration files

## File Locations and Precedence

Suitey looks for configuration files in the project root directory in the following order:

1. **`suitey.toml`** - Primary configuration file (TOML format)
2. **`.suiteyrc`** - Alternative configuration file (TOML format)

**Precedence**: If both files exist, `suitey.toml` takes precedence over `.suiteyrc`.

**Search Order**: Suitey first checks for `suitey.toml` in the project root directory. If found, it uses that file for configuration. If `suitey.toml` is not found, Suitey then checks for `.suiteyrc` in the project root. If neither configuration file exists, Suitey falls back to automatic detection using its adaptive detection strategies.

## Configuration File Format: suitey.toml

The `suitey.toml` file uses TOML (Tom's Obvious Minimal Language) format, which is human-readable and widely supported.

### Basic Structure

```toml
# Suitey Configuration File
# This file allows explicit definition of test suites

[[suites]]
name = "unit"
files = ["tests/unit/**/*", "src/**/*_test.*"]

[[suites]]
name = "integration"
files = ["tests/integration/**/*"]

[[suites]]
name = "e2e"
files = ["tests/e2e/**/*.spec.*"]
```

### Schema Definition

#### Root Level

The root of the configuration file contains:

- **`suites`** (array of tables, required): Array of test suite definitions
- **`build`** (table, optional): Build configuration
- **`execution`** (table, optional): Execution configuration
- **`reporting`** (table, optional): Reporting configuration

#### Suite Definition (`[[suites]]`)

Each suite definition is a table array entry with the following fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Unique identifier for the test suite |
| `files` | array of strings | Yes | Glob patterns matching test files for this suite |
| `platform` | string | No | Restrict suite to specific platform (e.g., "rust", "bash") |
| `framework` | string | No | Restrict suite to specific framework (e.g., "cargo", "bats") |
| `exclude` | array of strings | No | Glob patterns for files to exclude from this suite |
| `parallel` | boolean | No | Allow parallel execution (default: true) |
| `timeout` | integer | No | Maximum execution time in seconds (default: no timeout) |
| `requires_build` | boolean | No | Whether this suite requires building first (default: auto-detect) |
| `build_steps` | array of strings | No | Custom build commands for this suite |
| `environment` | table | No | Environment variables for test execution |
| `metadata` | table | No | Additional metadata key-value pairs |

#### Build Configuration (`[build]`)

Global build configuration:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `required` | boolean | No | Whether building is required (default: auto-detect) |
| `steps` | array of strings | No | Global build commands |
| `parallel` | boolean | No | Allow parallel builds (default: true) |
| `timeout` | integer | No | Maximum build time in seconds |

#### Execution Configuration (`[execution]`)

Global execution configuration:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parallel` | boolean | No | Allow parallel test execution (default: true) |
| `max_parallel` | integer | No | Maximum parallel test suites (default: CPU count) |
| `timeout` | integer | No | Global timeout for all suites in seconds |
| `retry_failed` | integer | No | Number of times to retry failed tests (default: 0) |

#### Reporting Configuration (`[reporting]`)

Report generation configuration:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `format` | array of strings | No | Report formats: "console", "html", "json" (default: ["console", "html"]) |
| `output_dir` | string | No | Directory for report files (default: "/tmp/suitey-reports") |
| `serve` | boolean | No | Serve HTML report via HTTP (default: true) |
| `port` | integer | No | Port for HTTP server (default: 8080) |

### Complete Example

```toml
# Suitey Configuration File
# Example configuration for a multi-platform project

# Test Suite Definitions
[[suites]]
name = "unit"
files = [
    "tests/unit/**/*.bats",
    "src/**/*_test.rs"
]
platform = "rust"
parallel = true
timeout = 300

[[suites]]
name = "integration"
files = ["tests/integration/**/*"]
exclude = ["tests/integration/legacy/**/*"]
parallel = true
requires_build = true

[[suites]]
name = "e2e"
files = ["tests/e2e/**/*.spec.*"]
platform = "bash"
framework = "bats"
parallel = false  # E2E tests run sequentially
timeout = 600
environment = { BROWSER = "chrome", HEADLESS = "true" }

[[suites]]
name = "code-quality"
files = ["**/*.sh"]
platform = "shell"
framework = "shellcheck"
parallel = true

# Build Configuration
[build]
required = true
steps = [
    "cargo build --release",
    "npm run build"
]
parallel = true
timeout = 1800

# Execution Configuration
[execution]
parallel = true
max_parallel = 4
timeout = 3600
retry_failed = 1

# Reporting Configuration
[reporting]
format = ["console", "html", "json"]
output_dir = "/tmp/suitey-reports"
serve = true
port = 8080
```

## Configuration File Format: .suiteyrc

The `.suiteyrc` file uses the same TOML format as `suitey.toml`. It serves as an alternative configuration file, typically used when:

- Users prefer hidden configuration files (dotfiles)
- Multiple configuration files are needed (though only one is used)
- Legacy or compatibility reasons

**Note**: `.suiteyrc` has identical schema and format to `suitey.toml`. The only difference is the filename and lower precedence.

## Glob Pattern Support

Both configuration files support glob patterns for file matching:

### Supported Patterns

- **`*`** - Matches any characters except path separators
- **`**`** - Matches any characters including path separators (recursive)
- **`?`** - Matches a single character
- **`[abc]`** - Matches any character in the set
- **`[!abc]`** - Matches any character not in the set
- **`{pattern1,pattern2}`** - Matches any of the patterns

### Pattern Examples

```toml
# Match all test files in tests directory recursively
files = ["tests/**/*"]

# Match specific file extensions
files = ["**/*.bats", "**/*_test.rs", "**/*.spec.js"]

# Match files in specific directories
files = ["src/**/*_test.*", "tests/unit/**/*"]

# Exclude patterns
exclude = ["**/node_modules/**", "**/target/**", "**/*.tmp"]
```

## Validation Rules

### Required Fields

- Each suite must have a `name` field
- Each suite must have a `files` array with at least one pattern

### Field Validation

- **`name`**: Must be a non-empty string, unique within the configuration file
- **`files`**: Must be a non-empty array of strings
- **`platform`**: Must match a detected platform (case-sensitive)
- **`framework`**: Must match a detected framework (case-sensitive)
- **`timeout`**: Must be a positive integer
- **`max_parallel`**: Must be a positive integer
- **`port`**: Must be a valid port number (1-65535)

### Error Handling

When configuration file parsing fails:

1. **Syntax Errors**: Log error and fall back to automatic detection
2. **Validation Errors**: Log specific field errors and fall back to automatic detection
3. **Missing Files**: Silently fall back to automatic detection (not an error)
4. **Invalid Patterns**: Log warning for invalid glob patterns, skip those patterns

## Integration with Detection Flow

Configuration files integrate with Suitey's adaptive detection strategy:

### Detection Priority Order

1. **Configuration-Driven** (highest priority)
   - Check for `suitey.toml` or `.suiteyrc`
   - Parse configuration file
   - Use defined suites

2. **Convention-Based**
   - Recognize standard directory patterns
   - Group by conventional names

3. **Subdirectory-Aware**
   - Preserve user organization
   - Group by subdirectory structure

4. **Directory-Based**
   - Group all files in directory as one suite

5. **File-Level** (lowest priority)
   - Each file becomes its own suite

### Configuration File Processing

```bash
process_configuration_file() {
    local project_root="$1"
    local config_file=""
    
    # Check for configuration files
    if [[ -f "$project_root/suitey.toml" ]]; then
        config_file="$project_root/suitey.toml"
    elif [[ -f "$project_root/.suiteyrc" ]]; then
        config_file="$project_root/.suiteyrc"
    else
        return 1  # No configuration file found
    fi
    
    # Parse configuration file
    # Extract suite definitions
    # Validate configuration
    # Return suite definitions in flat data format
    
    return 0
}
```

## Flat Data Format Conversion

Configuration files are parsed and converted to Suitey's internal flat data format for consistency with the rest of the system:

### Suite Definition Conversion

```toml
[[suites]]
name = "unit"
files = ["tests/unit/**/*"]
platform = "rust"
```

Converts to:

```
suites_count=1
suites_0_name=unit
suites_0_files_0=tests/unit/**/*
suites_0_files_count=1
suites_0_platform=rust
suites_0_parallel=true
suites_0_timeout=0
```

## Parsing Implementation Notes

### TOML Parsing in Bash

Since Suitey aims for zero external dependencies, TOML parsing should be implemented in pure Bash. Key considerations:

1. **Simple TOML Subset**: Support only the features needed for Suitey configuration
2. **Table Arrays**: Parse `[[suites]]` syntax
3. **String Arrays**: Parse `files = ["pattern1", "pattern2"]`
4. **Key-Value Pairs**: Parse simple assignments
5. **Comments**: Ignore `#` comments

### Parsing Strategy

```bash
parse_toml_config() {
    local config_file="$1"
    
    # Read file line by line
    # Track current section (suites, build, execution, reporting)
    # Parse table arrays [[suites]]
    # Extract key-value pairs
    # Convert to flat data format
    
    # Return flat data format string
}
```

## Examples

### Minimal Configuration

```toml
[[suites]]
name = "all-tests"
files = ["tests/**/*"]
```

### Multi-Platform Project

```toml
[[suites]]
name = "rust-unit"
files = ["src/**/*_test.rs"]
platform = "rust"

[[suites]]
name = "bash-tests"
files = ["tests/**/*.bats"]
platform = "bash"
```

### Complex Configuration

```toml
[[suites]]
name = "unit"
files = ["tests/unit/**/*"]
exclude = ["tests/unit/legacy/**/*"]
parallel = true
timeout = 300
environment = { NODE_ENV = "test", DEBUG = "false" }
metadata = { priority = "high", owner = "team-a" }

[[suites]]
name = "integration"
files = ["tests/integration/**/*"]
requires_build = true
build_steps = ["npm run build", "docker-compose up -d"]
parallel = false

[build]
required = true
steps = ["cargo build"]
parallel = true

[execution]
parallel = true
max_parallel = 4
retry_failed = 2

[reporting]
format = ["console", "html"]
serve = true
port = 8080
```

## Migration and Compatibility

### Versioning

Configuration files may include a version field in the future:

```toml
version = "1.0"

[[suites]]
# ...
```

### Backward Compatibility

- Unknown fields are ignored (no errors)
- Missing optional fields use defaults
- Invalid patterns are skipped with warnings

## Future Enhancements

Potential future additions to the configuration format:

1. **Suite Dependencies**: Define execution order
2. **Conditional Suites**: Enable suites based on conditions
3. **Suite Tags**: Tag suites for selective execution
4. **Custom Commands**: Define custom pre/post execution commands
5. **Resource Limits**: CPU/memory limits per suite
6. **Notification Configuration**: Configure notifications for test results

## References

- TOML Specification: https://toml.io/
- Suitey Detection Strategy: See `spec/SPEC.md` section "Adaptive Test Suite Detection"
- Flat Data Format: See `spec/DATA-CONVENTIONS.md`

