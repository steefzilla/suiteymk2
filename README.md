# Suitey

Suitey is a cross-platform test runner that automatically detects test suites, builds projects, and executes tests in isolated Docker containers.

## Quick Start

### 1. Clone the repository
```bash
git clone https://github.com/your-repo/suiteymk2.git
cd suiteymk2
```

### 2. Set up the project
```bash
./setup.sh
```

This will:
- Initialize git submodules (test dependencies)
- Check for required tools
- Verify everything is ready to use

### 3. Build the project (optional)
```bash
./build.sh
```

### 4. Run tests
```bash
# Run unit tests
bats tests/bats/unit/

# Run integration tests
bats tests/bats/integration/

# Run all tests
bats tests/bats/
```

## Requirements

### System Requirements
- **Docker**: Required for integration tests and container operations
- **Bash 4.0+**: For script execution
- **Git**: For repository operations

### Test Dependencies
- **BATS**: Test framework (automatically checked by setup.sh)
- **bats-support & bats-assert**: Test helper libraries (automatically set up via git submodules)

## Project Structure

```
suiteymk2/
├── src/                    # Source code
├── tests/bats/            # BATS test suite
│   ├── unit/             # Unit tests
│   └── integration/      # Integration tests
├── mod/                  # Language and framework modules
├── example/              # Example projects for testing
├── spec/                 # Specifications and documentation
├── build.sh              # Build script
├── setup.sh              # Setup script
└── suitey.sh             # Main executable
```

## Development

### Adding Tests
- Unit tests go in `tests/bats/unit/`
- Integration tests go in `tests/bats/integration/`
- Test helpers are automatically available via git submodules

### Building
```bash
# Build the main executable
./build.sh

# Create a minified version
./build.sh --minify

# See all build options
./build.sh --help
```

### Testing
```bash
# Run specific test file
bats tests/bats/unit/mod_registry.bats

# Run with verbose output
bats -t tests/bats/unit/

# Run parallel tests (faster)
bats -j 4 tests/bats/unit/
```

## Documentation

- **[Testing Guide](spec/TESTING.md)**: Comprehensive testing documentation
- **[Implementation Plan](IMPLEMENTATION-PLAN.md)**: Project roadmap and architecture
- **[Specifications](spec/)**: Detailed component specifications

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests: `bats tests/bats/`
5. Submit a pull request

## License

See individual component licenses. Test helper libraries (bats-support, bats-assert) maintain their original licenses.
