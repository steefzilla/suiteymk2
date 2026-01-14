# Suitey BATS Example Project

This is a sample BATS (Bash Automated Testing System) project for testing Suitey's platform detection capabilities.

## Project Structure

- `tests/bats/` - BATS test files
  - `basic_tests.bats` - Basic BATS test examples
  - `advanced_tests.bats` - Advanced BATS tests with assertions
- `tests/unit/` - Other test files
  - `shell_tests.sh` - Simple shell script tests

## Running Tests

```bash
# Run all BATS tests
bats tests/bats/

# Run specific test file
bats tests/bats/basic_tests.bats

# Run shell script tests
bash tests/unit/shell_tests.sh
```

## Suitey Detection

This project demonstrates:
- `.bats` file detection for high confidence BATS platform identification
- Test directory structure recognition
- Suitey should detect this as a "Bash project with high confidence" and "BATS framework"

## Test Categories

- **Unit Tests**: Individual function/component testing
- **Integration Tests**: Cross-component testing
- **BATS Framework**: Test framework using BATS syntax


