# Data Conventions Specification

## Overview

Suitey uses a simple, line-based flat data format for component communication. It requires no external dependencies. This format is used throughout the Suitey Modules system for passing structured data between components.

## Goals

1. **Zero Dependencies**: No external tools required (pure Bash)
2. **Human Readable**: Easy to maintain
3. **Simple Parsing**: Uses standard Unix tools
4. **Flat Structure**: Simple key=value pairs with naming conventions instead of nested objects
5. **Arrays Support**: Via indexed naming conventions (`array_0=value`, `array_count=N`)
6. **Multi-line Support**: Via heredoc-style syntax
7. **Suitey Modules Integration**: Designed specifically for Suitey Modules data exchange
8. **Filesystem Isolation**: All data handling respects Suitey's principle of not modifying the host filesystem except for `/tmp`

## Format Specification

### Basic Key-Value Pairs

```
key=value
detected=true
confidence=high
framework=bats
```

### Flat Naming Conventions for Grouping

Related properties are grouped using prefixes:

```
test_image_name=suitey-test-rust-20240115
test_image_id=sha256:abc123
test_image_dockerfile_path=/tmp/build/Dockerfile
```

### Arrays with Indexed Naming

Arrays use numbered indices with a count:

```
test_files_0=/path/to/test1.bats
test_files_1=/path/to/test2.bats
test_files_count=2
```

**Note**: Arrays always include a `_count` field indicating the number of elements.

### Sections for Grouping

Sections can be used to group related data:

```
[suite:unit_tests]
name=unit
framework=bats
test_files_0=tests/unit/test1.bats
test_files_count=1

[suite:integration_tests]
name=integration
framework=bats
test_files_0=tests/integration/test1.bats
test_files_count=1
```

### Multi-line Values (Heredoc-style)

For fields that may contain newlines (like `output`):

```
output<<EOF
1..3
ok 1 test1
ok 2 test2
ok 3 test3
EOF
```

### Special Values

- **Empty strings**: `key=`
- **Null values**: `key=null` (explicit null) or `key=` (implicit empty)
- **Booleans**: `key=true` or `key=false`
- **Numbers**: `duration=1.5`, `exit_code=0` (stored as strings, parsed as needed)

### Escaping

Values containing special characters (`=`, newlines, etc.) should use heredoc syntax. Simple values with spaces don't need quotes, but can be quoted if desired:

```
name="My Test Suite"
```

## Data Structure Examples

### Detection Result

**Flat Format:**
```
detected=true
confidence=high
indicators_0=file_extension
indicators_1=directory_pattern
indicators_count=2
framework_info_name=BATS
framework_info_identifier=bats
```

### Test Suite Array

**Flat Format:**
```
suites_count=2
suites_0_name=unit
suites_0_framework=bats
suites_0_test_files_0=tests/unit/test1.bats
suites_0_test_files_count=1
suites_1_name=integration
suites_1_framework=bats
suites_1_test_files_0=tests/integration/test1.bats
suites_1_test_files_count=1
```

### Execution Result

**Flat Format:**
```
exit_code=0
duration=1.5
container_id=abc123
test_image_name=suitey-test-rust
test_image_id=sha256:def456
output<<EOF
1..3
ok 1 test1
ok 2 test2
ok 3 test3
EOF
```

### Build Requirements

**Flat Format:**
```
requires_build=true
build_steps_count=1
build_steps_0_step_name=install_deps
build_steps_0_build_command=cargo build
build_dependencies_count=0
```

## Data Access Functions Specification

### File: `src/data_access.sh`

This file provides functions for accessing and manipulating data in the flat data format. All functions are pure Bash implementations with no external dependencies.

### Core Data Access Functions

#### `data_get(data: string, key: string) -> string`

**Description**: Extracts a value from data using a key path.

**Inputs**:
- `data`: Data format string containing key-value pairs
- `key`: Key path (e.g., "test_image_name")

**Outputs**:
- Returns: Extracted value as string, or empty string if not found
- Exit code: 0 on success, 1 on error (empty inputs)

**Behavior**:
- Searches for the first occurrence of `key=` in the data
- Extracts everything after the `=` sign
- Removes surrounding quotes if present
- Unescapes escaped quotes within quoted values

---

#### `data_get_array(data: string, array_name: string, index: number) -> string`

**Description**: Extracts an array element from data by index.

**Inputs**:
- `data`: Data format string
- `array_name`: Name of the array (without index suffix)
- `index`: Array index (0-based, must be numeric)

**Outputs**:
- Returns: Array element value, or empty if not found
- Exit code: 0 on success, 1 on error (invalid inputs)

**Behavior**:
- Constructs key as `${array_name}_${index}`
- Calls `data_get()` with the constructed key

---

#### `data_array_count(data: string, array_name: string) -> number`

**Description**: Gets the count of elements in an array.

**Inputs**:
- `data`: Data format string
- `array_name`: Name of the array

**Outputs**:
- Returns: Array count as integer string, or "0" if not found/invalid
- Exit code: 0 on success, 1 if count field missing

**Behavior**:
- Looks for `${array_name}_count` key
- Validates that the value is numeric
- Returns "0" if count field is missing or non-numeric

---

#### `data_get_array_all(data: string, array_name: string) -> string[]`

**Description**: Extracts all elements from an array.

**Inputs**:
- `data`: Data format string
- `array_name`: Name of the array

**Outputs**:
- Returns: Array elements, one per line (stdout), or empty if array doesn't exist
- Exit code: 0 on success

**Behavior**:
- Gets array count using `data_array_count()`
- Iterates from 0 to count-1
- Calls `data_get_array()` for each index
- Outputs each element on a separate line

---

#### `data_has_key(data: string, key: string) -> boolean`

**Description**: Checks if a key exists in data.

**Inputs**:
- `data`: Data format string
- `key`: Key to check

**Outputs**:
- Exit code: 0 if key exists, 1 if not found or invalid inputs

**Behavior**:
- Searches for lines starting with `${key}=`
- Returns success if found, failure otherwise

---

### Data Modification Functions

#### `data_set(data: string, key: string, value: string) -> string`

**Description**: Sets a value in data, creating new data with updated value.

**Inputs**:
- `data`: Original data string
- `key`: Key to set
- `value`: New value (will be escaped if needed)

**Outputs**:
- Returns: Updated data string (stdout)
- Exit code: 0 on success, 1 if key is empty

**Behavior**:
- Removes existing key if present (including multi-line heredoc blocks)
- Escapes value if it contains special characters (spaces, $, `, ", \)
- Wraps escaped values in quotes
- Appends new key-value pair to data
- Returns updated data string

---

#### `data_array_append(data: string, array_name: string, value: string) -> string`

**Description**: Appends a value to an array.

**Inputs**:
- `data`: Data format string
- `array_name`: Name of the array
- `value`: Value to append

**Outputs**:
- Returns: Updated data string with new array element
- Exit code: 0 on success

**Behavior**:
- Gets current array count using `data_array_count()`
- Sets new element at index `count` using `data_set()`
- Updates count to `count + 1` using `data_set()`
- Returns updated data string

---

#### `data_set_array(data: string, array_name: string, values: string[]) -> string`

**Description**: Sets an entire array, replacing any existing array entries.

**Inputs**:
- `data`: Data format string
- `array_name`: Name of the array
- `values`: Array of values to set (variable arguments)

**Outputs**:
- Returns: Updated data string
- Exit code: 0 on success

**Behavior**:
- Removes all existing array entries (`${array_name}_N=` and `${array_name}_count=`)
- Adds new entries for each value at sequential indices
- Sets count to number of values added
- Returns updated data string

---

#### `data_set_multiline(data: string, key: string, value: string) -> string`

**Description**: Sets a multi-line value using heredoc syntax.

**Inputs**:
- `data`: Data format string
- `key`: Key name
- `value`: Multi-line value

**Outputs**:
- Returns: Updated data string with heredoc syntax
- Exit code: 0 on success

**Behavior**:
- Removes existing heredoc block if present (lines between `${key}<<EOF` and `EOF`)
- Removes regular `key=value` entry for this key if present
- Appends new heredoc block: `${key}<<EOF`, value lines, `EOF`
- Returns updated data string

---

#### `data_get_multiline(data: string, key: string) -> string`

**Description**: Gets a multi-line value, handling heredoc syntax.

**Inputs**:
- `data`: Data format string
- `key`: Key name

**Outputs**:
- Returns: Multi-line value (without heredoc markers), or single-line value
- Exit code: 0 on success, 1 on error (invalid inputs)

**Behavior**:
- Checks if key uses heredoc syntax (`${key}<<EOF`)
- If heredoc: extracts content between `${key}<<EOF` and `EOF` markers
- If not heredoc: calls `data_get()` for regular single-line value
- Returns extracted value

---

### Data Validation Functions

#### `data_validate(data: string) -> boolean`

**Description**: Validates that a string conforms to the data format specification.

**Inputs**:
- `data`: String to validate

**Outputs**:
- Exit code: 0 if valid data format, 1 if invalid

**Behavior**:
- Empty input is considered valid
- Validates each line:
  - Allows empty lines
  - Allows comment lines (starting with `#`)
  - Allows section headers (`[section_name]`)
  - Allows heredoc start markers (`key<<EOF`)
  - Allows heredoc end markers (`EOF`)
  - Requires other lines to match `key=value` pattern
- Returns success if all lines are valid, failure otherwise

## Testing Plan

### Unit Tests
- **Data Access Tests**: Key extraction, array handling, validation
- **Build Manager Tests**: Docker orchestration, container management, build execution (with mocking)
- **Platform Detector Tests**: Platform detection logic
- **Project Scanner Tests**: Project structure analysis
- **Performance Tests**: Concurrency, I/O, memory, startup
- **Security Tests**: Input validation, path traversal, permissions, temp files
- **Static Analysis Tests**: Code quality, complexity, dead code detection

### Integration Tests
- **Build Manager Integration**: Real Docker operations, container lifecycle, image building
- **Suitey Modules Registry Integration**: Platform detection, project scanning, test suite detection
- **End-to-End Workflows**: Complete test execution flows

## Notes

- **Performance**: Data parsing should be efficient for Suitey's use cases
- **Debugging**: Data files are easier to read and debug than JSON
- **Escaping**: Simple values don't need escaping; complex values use heredoc syntax
- **Arrays**: Always include `_count` field for efficient iteration

## Open Questions

1. Should we support comments in data? (lines starting with `#`)
2. Should we support empty sections?
3. How to handle very large multi-line values?
4. Should we support nested sections?
5. Performance optimization: cache parsed data?
