# Suitey Tool Module: ShellCheck

## Overview

The ShellCheck tool module orchestrates [ShellCheck](https://github.com/koalaman/shellcheck) for shell script code quality analysis. ShellCheck is a static analysis tool that gives warnings and suggestions for shell scripts.

## Purpose

This module detects shell scripts in a project and runs ShellCheck on them to identify common issues, potential bugs, and style violations in shell scripts.

## Detection

The module detects projects that contain shell scripts (`.sh` files) and automatically creates a code quality test suite to run ShellCheck analysis.

## Container Requirements

- **Image**: `koalaman/shellcheck:latest`
- **Command**: `shellcheck --format=json <script files>`

## Example Usage

When a project contains shell scripts like:

```
project/
├── build.sh
├── scripts/
│   ├── deploy.sh
│   └── utils.sh
└── test.sh
```

The module will:
1. Detect the presence of shell scripts
2. Create a "shellcheck" test suite
3. Run ShellCheck on all `.sh` files in containers
4. Parse the JSON output for issues and warnings
5. Report results in Suitey's standard format

## Configuration

No additional configuration is required. The module automatically discovers all `.sh` files in the project directory.

## Dependencies

- Docker (for containerized execution)
- `koalaman/shellcheck` Docker image (pulled automatically)

## Integration

This tool module integrates with Suitey's detection and execution phases:

- **Detection Phase**: Scans for shell scripts and determines if ShellCheck should run
- **Execution Phase**: Runs ShellCheck in containers and collects results
- **Reporting Phase**: Formats ShellCheck output as test results

## Output Format

ShellCheck results are parsed from JSON format and converted to Suitey's flat data format:

```
total_tests=3
passed_tests=1
failed_tests=2
test_details_0=SC1001: This is an error
test_details_1=SC2001: Use $(...) instead of legacy backticks
status=failed
```

## Limitations

- Only analyzes `.sh` files (not other shell script extensions)
- Requires Docker for execution
- Uses mock results in current implementation (pending full Docker integration)