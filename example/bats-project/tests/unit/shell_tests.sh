#!/bin/bash
# Simple shell script tests
# These are not BATS tests but demonstrate shell script detection

echo "Running shell script tests..."

# Test basic shell operations
test_count=0
pass_count=0

# Test 1: Basic arithmetic
result=$((5 + 3))
if [ "$result" -eq 8 ]; then
    echo "✓ Arithmetic test passed"
    ((pass_count++))
else
    echo "✗ Arithmetic test failed"
fi
((test_count++))

# Test 2: String operations
test_string="suitey"
if [ "${#test_string}" -eq 6 ]; then
    echo "✓ String length test passed"
    ((pass_count++))
else
    echo "✗ String length test failed"
fi
((test_count++))

# Test 3: File operations
temp_file="/tmp/shell_test_$$.tmp"
echo "test" > "$temp_file"
if [ -f "$temp_file" ] && [ "$(cat "$temp_file")" = "test" ]; then
    echo "✓ File operations test passed"
    ((pass_count++))
else
    echo "✗ File operations test failed"
fi
((test_count++))

rm -f "$temp_file"

echo "Tests completed: $pass_count/$test_count passed"

