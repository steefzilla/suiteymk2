#!/usr/bin/env bash

# Verbose Formatter
# Streams raw test output to stdout/stderr with suite identification prefixes
# Buffers output by suite for readability

# =============================================================================
# Global State for Output Buffering
# =============================================================================

# Associative arrays for buffer management (require Bash 4+)
# Use -g flag for global scope when in functions
if [[ -z "${OUTPUT_BUFFERS_INITIALIZED:-}" ]]; then
    declare -gA OUTPUT_BUFFERS 2>/dev/null || declare -A OUTPUT_BUFFERS
    declare -gA BUFFER_TIMESTAMPS 2>/dev/null || declare -A BUFFER_TIMESTAMPS
    declare -gA BUFFER_INITIALIZED 2>/dev/null || declare -A BUFFER_INITIALIZED
    OUTPUT_BUFFERS_INITIALIZED="true"
fi

# List of active buffer suite IDs
ACTIVE_BUFFER_SUITES="${ACTIVE_BUFFER_SUITES:-}"

# Verbose mode state
VERBOSE_MODE_ACTIVE="${VERBOSE_MODE_ACTIVE:-}"

# Default flush interval in milliseconds
DEFAULT_FLUSH_INTERVAL_MS=100

# =============================================================================
# Output Line Formatting
# =============================================================================

# Format a single line or multiline output with suite identification prefix
# Usage: format_output_line <suite_id> <output_content>
# Returns: Formatted output with [suite_id] prefix on each line
format_output_line() {
    local suite_id="$1"
    local content="$2"

    # Handle empty content
    if [[ -z "$content" ]]; then
        echo "[$suite_id]"
        return 0
    fi

    # Add prefix to each line
    while IFS= read -r line || [[ -n "$line" ]]; do
        echo "[$suite_id] $line"
    done <<< "$content"

    return 0
}

# Stream output from a file with suite prefix
# Usage: stream_suite_output <suite_id> <output_file>
# Returns: Streams formatted output to stdout
stream_suite_output() {
    local suite_id="$1"
    local output_file="$2"

    # Check if file exists
    if [[ ! -f "$output_file" ]]; then
        return 0  # Gracefully handle missing file
    fi

    # Stream file contents with prefix
    while IFS= read -r line || [[ -n "$line" ]]; do
        echo "[$suite_id] $line"
    done < "$output_file"

    return 0
}

# =============================================================================
# Output Buffering Functions
# =============================================================================

# Initialize output buffer for a suite
# Usage: init_output_buffer <suite_id>
# Returns: Buffer initialization status in flat data format
init_output_buffer() {
    local suite_id="$1"

    # Initialize buffer storage
    OUTPUT_BUFFERS[$suite_id]=""
    BUFFER_TIMESTAMPS[$suite_id]=$(date +%s%N 2>/dev/null || date +%s)
    BUFFER_INITIALIZED[$suite_id]="true"

    # Track active suites
    if [[ "$ACTIVE_BUFFER_SUITES" != *"$suite_id"* ]]; then
        if [[ -z "$ACTIVE_BUFFER_SUITES" ]]; then
            ACTIVE_BUFFER_SUITES="$suite_id"
        else
            ACTIVE_BUFFER_SUITES="$ACTIVE_BUFFER_SUITES|$suite_id"
        fi
    fi

    echo "buffer_initialized=true"
    echo "suite_id=$suite_id"

    return 0
}

# Add content to suite buffer
# Usage: buffer_output <suite_id> <content>
# Returns: Buffer status in flat data format
buffer_output() {
    local suite_id="$1"
    local content="$2"

    # Initialize if not already done
    if [[ "${BUFFER_INITIALIZED[$suite_id]}" != "true" ]]; then
        init_output_buffer "$suite_id" >/dev/null 2>&1
    fi

    # Append to buffer
    if [[ -z "${OUTPUT_BUFFERS[$suite_id]}" ]]; then
        OUTPUT_BUFFERS[$suite_id]="$content"
    else
        OUTPUT_BUFFERS[$suite_id]="${OUTPUT_BUFFERS[$suite_id]}"$'\n'"$content"
    fi

    # Update timestamp
    BUFFER_TIMESTAMPS[$suite_id]=$(date +%s%N 2>/dev/null || date +%s)

    echo "buffered=true"
    echo "suite_id=$suite_id"

    return 0
}

# Get buffer contents for a suite
# Usage: get_buffer_contents <suite_id>
# Returns: Buffer contents in flat data format
get_buffer_contents() {
    local suite_id="$1"

    # Get content, ensuring we only get this specific suite's content
    local content=""
    if [[ -n "${OUTPUT_BUFFERS[$suite_id]+x}" ]]; then
        content="${OUTPUT_BUFFERS[$suite_id]}"
    fi

    echo "suite_id=$suite_id"
    # Use a delimiter that's unlikely to appear in content
    if [[ -n "$content" ]]; then
        echo "content=$content"
    else
        echo "content="
    fi

    return 0
}

# Flush output buffer for a suite (output with prefix and clear)
# Usage: flush_output_buffer <suite_id>
# Returns: Outputs buffered content with suite prefix
flush_output_buffer() {
    local suite_id="$1"

    # Get buffer content
    local content="${OUTPUT_BUFFERS[$suite_id]:-}"

    # Output with prefix if there's content
    if [[ -n "$content" ]]; then
        format_output_line "$suite_id" "$content"
    fi

    # Clear the buffer
    OUTPUT_BUFFERS[$suite_id]=""

    return 0
}

# Clear output buffer without flushing
# Usage: clear_output_buffer <suite_id>
# Returns: Status in flat data format
clear_output_buffer() {
    local suite_id="$1"

    # Explicitly unset and re-initialize to empty
    unset 'OUTPUT_BUFFERS[$suite_id]'
    OUTPUT_BUFFERS[$suite_id]=""

    echo "cleared=true"
    echo "suite_id=$suite_id"

    return 0
}

# Get list of active buffers
# Usage: get_active_buffers
# Returns: List of active suite IDs
get_active_buffers() {
    local suites=""

    # Parse the pipe-separated list
    if [[ -n "$ACTIVE_BUFFER_SUITES" ]]; then
        local IFS='|'
        for suite in $ACTIVE_BUFFER_SUITES; do
            if [[ -n "$suite" ]]; then
                echo "active_suite=$suite"
                suites="$suites $suite"
            fi
        done
    fi

    echo "active_count=$(echo "$ACTIVE_BUFFER_SUITES" | tr '|' '\n' | grep -c . || echo "0")"

    return 0
}

# =============================================================================
# Flush Interval Management
# =============================================================================

# Get the buffer flush interval
# Usage: get_buffer_flush_interval
# Returns: Flush interval in flat data format
get_buffer_flush_interval() {
    local interval_ms="${SUITEY_BUFFER_FLUSH_INTERVAL_MS:-$DEFAULT_FLUSH_INTERVAL_MS}"

    echo "flush_interval_ms=$interval_ms"

    return 0
}

# Check if a buffer should be flushed based on elapsed time
# Usage: should_flush_buffer <suite_id>
# Returns: Whether buffer should be flushed in flat data format
should_flush_buffer() {
    local suite_id="$1"

    # Get flush interval
    local interval_ms="${SUITEY_BUFFER_FLUSH_INTERVAL_MS:-$DEFAULT_FLUSH_INTERVAL_MS}"

    # Get buffer timestamp
    local buffer_time="${BUFFER_TIMESTAMPS[$suite_id]:-0}"
    local current_time=$(date +%s%N 2>/dev/null || date +%s)

    # Calculate elapsed time in nanoseconds, then convert to milliseconds
    local elapsed_ns=$((current_time - buffer_time))
    local elapsed_ms=$((elapsed_ns / 1000000))

    # Handle systems without nanosecond precision
    if [[ "$elapsed_ms" -lt 0 ]] || [[ "$elapsed_ms" -gt 1000000 ]]; then
        # Fallback: use seconds
        elapsed_ms=$(( (current_time - buffer_time) * 1000 ))
    fi

    if [[ "$elapsed_ms" -ge "$interval_ms" ]]; then
        echo "should_flush=true"
        echo "elapsed_ms=$elapsed_ms"
    else
        echo "should_flush=false"
        echo "elapsed_ms=$elapsed_ms"
    fi

    return 0
}

# Automatically flush all buffers that have exceeded their interval
# Usage: auto_flush_buffers
# Returns: Outputs all flushed content
auto_flush_buffers() {
    local flushed_count=0

    # Iterate through active suites
    if [[ -n "$ACTIVE_BUFFER_SUITES" ]]; then
        local IFS='|'
        for suite_id in $ACTIVE_BUFFER_SUITES; do
            if [[ -n "$suite_id" ]]; then
                # Check if should flush
                local flush_check
                flush_check=$(should_flush_buffer "$suite_id" 2>/dev/null)
                local should_flush
                should_flush=$(echo "$flush_check" | grep "^should_flush=" | cut -d'=' -f2)

                if [[ "$should_flush" == "true" ]]; then
                    flush_output_buffer "$suite_id"
                    ((flushed_count++))
                fi
            fi
        done
    fi

    echo "flushed_count=$flushed_count"

    return 0
}

# =============================================================================
# Verbose Formatter Integration
# =============================================================================

# Format a test result for verbose output
# Usage: verbose_format_result <test_result_data>
# Returns: Formatted verbose output
verbose_format_result() {
    local result_data="$1"

    # Parse result data
    local suite_id test_status exit_code duration
    local total_tests passed_tests failed_tests
    local stdout stderr

    suite_id=$(echo "$result_data" | grep "^suite_id=" | cut -d'=' -f2)
    test_status=$(echo "$result_data" | grep "^test_status=" | cut -d'=' -f2)
    exit_code=$(echo "$result_data" | grep "^exit_code=" | cut -d'=' -f2)
    duration=$(echo "$result_data" | grep "^duration=" | cut -d'=' -f2)
    total_tests=$(echo "$result_data" | grep "^total_tests=" | cut -d'=' -f2)
    passed_tests=$(echo "$result_data" | grep "^passed_tests=" | cut -d'=' -f2)
    failed_tests=$(echo "$result_data" | grep "^failed_tests=" | cut -d'=' -f2)
    stdout=$(echo "$result_data" | grep "^stdout=" | cut -d'=' -f2-)
    stderr=$(echo "$result_data" | grep "^stderr=" | cut -d'=' -f2-)

    # Format output header
    echo "[$suite_id] ══════════════════════════════════════"
    echo "[$suite_id] Status: $test_status"

    if [[ -n "$duration" ]]; then
        echo "[$suite_id] Duration: ${duration}s"
    fi

    if [[ -n "$total_tests" ]]; then
        echo "[$suite_id] Tests: $total_tests total, $passed_tests passed, $failed_tests failed"
    fi

    # Output stdout if present
    if [[ -n "$stdout" ]]; then
        echo "[$suite_id] Output: $stdout"
    fi

    # Output stderr if present (for failures)
    if [[ -n "$stderr" ]] && [[ "$test_status" == "failed" ]]; then
        echo "[$suite_id] Error: $stderr"
    fi

    echo "[$suite_id] ══════════════════════════════════════"

    return 0
}

# Start verbose streaming mode
# Usage: start_verbose_streaming
# Returns: Status in flat data format
start_verbose_streaming() {
    VERBOSE_MODE_ACTIVE="true"

    echo "verbose_mode=active"
    echo "status=started"

    return 0
}

# Stop verbose streaming and flush all remaining buffers
# Usage: stop_verbose_streaming
# Returns: Final output and status
stop_verbose_streaming() {
    # Flush all remaining buffers
    if [[ -n "$ACTIVE_BUFFER_SUITES" ]]; then
        local IFS='|'
        for suite_id in $ACTIVE_BUFFER_SUITES; do
            if [[ -n "$suite_id" ]]; then
                flush_output_buffer "$suite_id"
            fi
        done
    fi

    VERBOSE_MODE_ACTIVE=""

    echo "verbose_mode=inactive"
    echo "status=stopped"

    return 0
}

# Check if verbose mode is active
# Usage: is_verbose_mode_active
# Returns: true/false
is_verbose_mode_active() {
    if [[ "$VERBOSE_MODE_ACTIVE" == "true" ]]; then
        echo "true"
        return 0
    else
        echo "false"
        return 1
    fi
}

