# Suitey Rust+BATS Example Project

This is a rust+bats example project containing both Rust and BATS indicators for testing Suitey's ability to detect multiple platforms in a single project.

## Project Structure

- `Cargo.toml` & `src/lib.rs` - Rust language detection
- `tests/bats/` - BATS framework detection

## Suitey Detection

This project demonstrates:
- Detection of multiple platforms in a single project
- Rust project detected as "rust project (high confidence)" with cargo framework
- BATS project detected as "bash project (high confidence)" with bats framework

## Running Tests

```bash
# Run BATS tests
bats tests/bats/

# Run Rust tests
cargo test
```
