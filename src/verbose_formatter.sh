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

# =============================================================================
# Post-Completion Output (4.1.2)
# =============================================================================

# Global state for execution records
# Format: suite_id|status|duration|timestamp
EXECUTION_RECORDS="${EXECUTION_RECORDS:-}"
EXECUTION_RECORD_COUNT=0

# Associative arrays for failure/error details
if [[ -z "${FAILURE_DETAILS_INITIALIZED:-}" ]]; then
    declare -gA FAILURE_STACK_TRACES 2>/dev/null || declare -A FAILURE_STACK_TRACES
    declare -gA FAILURE_MESSAGES 2>/dev/null || declare -A FAILURE_MESSAGES
    declare -gA ERROR_STACK_TRACES 2>/dev/null || declare -A ERROR_STACK_TRACES
    declare -gA ERROR_MESSAGES 2>/dev/null || declare -A ERROR_MESSAGES
    FAILURE_DETAILS_INITIALIZED="true"
fi

# Record a test execution with timestamp for ordering
# Usage: record_test_execution <suite_id> <status> <duration>
# Returns: Recording status in flat data format
record_test_execution() {
    local suite_id="$1"
    local status="$2"
    local duration="$3"
    local timestamp
    timestamp=$(date +%s%N 2>/dev/null || date +%s)

    # Create record entry
    local record="$suite_id|$status|$duration|$timestamp"

    # Append to records
    if [[ -z "$EXECUTION_RECORDS" ]]; then
        EXECUTION_RECORDS="$record"
    else
        EXECUTION_RECORDS="$EXECUTION_RECORDS"$'\n'"$record"
    fi
    ((EXECUTION_RECORD_COUNT++))

    echo "recorded=true"
    echo "suite_id=$suite_id"
    echo "status=$status"
    echo "record_index=$EXECUTION_RECORD_COUNT"

    return 0
}

# Get execution record for a specific suite
# Usage: get_execution_record <suite_id>
# Returns: Execution record in flat data format
get_execution_record() {
    local suite_id="$1"

    # Search for the record
    while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
        if [[ "$rec_suite" == "$suite_id" ]]; then
            echo "suite_id=$rec_suite"
            echo "status=$rec_status"
            echo "duration=$rec_duration"
            echo "timestamp=$rec_timestamp"
            return 0
        fi
    done <<< "$EXECUTION_RECORDS"

    echo "suite_id=$suite_id"
    echo "found=false"
    return 1
}

# Get all suites in execution order
# Usage: get_execution_order
# Returns: Suites in execution order in flat data format
get_execution_order() {
    local count=0

    # Parse records (they are already in execution order)
    while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
        if [[ -n "$rec_suite" ]]; then
            echo "suite_id=$rec_suite"
            echo "order_${count}_suite=$rec_suite"
            echo "order_${count}_status=$rec_status"
            echo "order_${count}_duration=$rec_duration"
            ((count++))
        fi
    done <<< "$EXECUTION_RECORDS"

    echo "total_ordered=$count"

    return 0
}

# Record a test failure with stack trace
# Usage: record_test_failure <suite_id> <stack_trace> <error_message>
# Returns: Recording status in flat data format
record_test_failure() {
    local suite_id="$1"
    local stack_trace="$2"
    local error_message="$3"

    FAILURE_STACK_TRACES[$suite_id]="$stack_trace"
    FAILURE_MESSAGES[$suite_id]="$error_message"

    echo "failure_recorded=true"
    echo "suite_id=$suite_id"

    return 0
}

# Get failure details for a suite
# Usage: get_failure_details <suite_id>
# Returns: Failure details in flat data format
get_failure_details() {
    local suite_id="$1"

    local stack_trace="${FAILURE_STACK_TRACES[$suite_id]:-}"
    local error_message="${FAILURE_MESSAGES[$suite_id]:-}"

    echo "suite_id=$suite_id"
    echo "stack_trace=$stack_trace"
    echo "error_message=$error_message"

    if [[ -n "$stack_trace" ]] || [[ -n "$error_message" ]]; then
        echo "has_details=true"
    else
        echo "has_details=false"
    fi

    return 0
}

# Format failure output with stack trace
# Usage: format_failure_output <suite_id> <stack_trace> <error_message>
# Returns: Formatted failure output
format_failure_output() {
    local suite_id="$1"
    local stack_trace="$2"
    local error_message="$3"

    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "  FAILURE: $suite_id"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Error: $error_message"
    echo ""
    echo "  Stack Trace:"
    
    # Format each line of stack trace with indentation
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" ]]; then
            echo "    $line"
        fi
    done <<< "$stack_trace"
    
    echo ""

    return 0
}

# Record a test error with stack trace
# Usage: record_test_error <suite_id> <stack_trace> <error_message>
# Returns: Recording status in flat data format
record_test_error() {
    local suite_id="$1"
    local stack_trace="$2"
    local error_message="$3"

    ERROR_STACK_TRACES[$suite_id]="$stack_trace"
    ERROR_MESSAGES[$suite_id]="$error_message"

    echo "error_recorded=true"
    echo "suite_id=$suite_id"

    return 0
}

# Get error details for a suite
# Usage: get_error_details <suite_id>
# Returns: Error details in flat data format
get_error_details() {
    local suite_id="$1"

    local stack_trace="${ERROR_STACK_TRACES[$suite_id]:-}"
    local error_message="${ERROR_MESSAGES[$suite_id]:-}"

    echo "suite_id=$suite_id"
    echo "stack_trace=$stack_trace"
    echo "error_message=$error_message"

    if [[ -n "$stack_trace" ]] || [[ -n "$error_message" ]]; then
        echo "has_details=true"
    else
        echo "has_details=false"
    fi

    return 0
}

# Format error output with stack trace (distinct from failures)
# Usage: format_error_output <suite_id> <stack_trace> <error_message>
# Returns: Formatted error output
format_error_output() {
    local suite_id="$1"
    local stack_trace="$2"
    local error_message="$3"

    echo ""
    echo "██████████████████████████████████████████████████████████████████"
    echo "  ERROR: $suite_id"
    echo "██████████████████████████████████████████████████████████████████"
    echo ""
    echo "  Error: $error_message"
    echo ""
    echo "  Stack Trace:"
    
    # Format each line of stack trace with indentation
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -n "$line" ]]; then
            echo "    $line"
        fi
    done <<< "$stack_trace"
    
    echo ""

    return 0
}

# Format post-completion summary with all results
# Usage: format_post_completion_summary
# Returns: Formatted summary output
format_post_completion_summary() {
    local total_suites=0
    local passed_suites=0
    local failed_suites=0
    local error_suites=0
    local total_duration=0

    # Header
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                      TEST EXECUTION SUMMARY                       ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""

    # Process all execution records in order
    echo "Test Results (in execution order):"
    echo "──────────────────────────────────────────────────────────────────"
    
    while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
        if [[ -n "$rec_suite" ]]; then
            ((total_suites++))
            
            # Calculate total duration
            if [[ -n "$rec_duration" ]]; then
                total_duration=$(echo "$total_duration + $rec_duration" | bc 2>/dev/null || echo "$total_duration")
            fi

            # Count by status
            case "$rec_status" in
                passed)
                    ((passed_suites++))
                    echo "  ✓ $rec_suite (${rec_duration}s) - PASSED"
                    ;;
                failed)
                    ((failed_suites++))
                    echo "  ✗ $rec_suite (${rec_duration}s) - FAILED"
                    ;;
                error)
                    ((error_suites++))
                    echo "  ⚠ $rec_suite (${rec_duration}s) - ERROR"
                    ;;
                *)
                    echo "  ? $rec_suite (${rec_duration}s) - $rec_status"
                    ;;
            esac
        fi
    done <<< "$EXECUTION_RECORDS"

    echo ""

    # Display failures with stack traces
    if [[ $failed_suites -gt 0 ]]; then
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                           FAILURES                                ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        
        while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
            if [[ "$rec_status" == "failed" ]] && [[ -n "$rec_suite" ]]; then
                local stack_trace="${FAILURE_STACK_TRACES[$rec_suite]:-}"
                local error_msg="${FAILURE_MESSAGES[$rec_suite]:-No details available}"
                format_failure_output "$rec_suite" "$stack_trace" "$error_msg"
            fi
        done <<< "$EXECUTION_RECORDS"
    fi

    # Display errors with stack traces
    if [[ $error_suites -gt 0 ]]; then
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                            ERRORS                                 ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        
        while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
            if [[ "$rec_status" == "error" ]] && [[ -n "$rec_suite" ]]; then
                local stack_trace="${ERROR_STACK_TRACES[$rec_suite]:-}"
                local error_msg="${ERROR_MESSAGES[$rec_suite]:-No details available}"
                format_error_output "$rec_suite" "$stack_trace" "$error_msg"
            fi
        done <<< "$EXECUTION_RECORDS"
    fi

    # Summary statistics
    echo "══════════════════════════════════════════════════════════════════"
    echo "  SUMMARY"
    echo "══════════════════════════════════════════════════════════════════"
    echo ""
    echo "  Total Suites:  $total_suites"
    echo "  Passed:        $passed_suites"
    echo "  Failed:        $failed_suites"
    echo "  Errors:        $error_suites"
    echo "  Total Time:    ${total_duration}s"
    echo ""

    # Final status
    if [[ $failed_suites -eq 0 ]] && [[ $error_suites -eq 0 ]]; then
        echo "  ✓ All tests passed!"
    else
        echo "  ✗ Some tests did not pass."
    fi
    echo ""

    return 0
}

# Clear all execution records
# Usage: clear_execution_records
# Returns: Status in flat data format
clear_execution_records() {
    EXECUTION_RECORDS=""
    EXECUTION_RECORD_COUNT=0

    # Clear failure details
    for key in "${!FAILURE_STACK_TRACES[@]}"; do
        unset 'FAILURE_STACK_TRACES[$key]'
    done
    for key in "${!FAILURE_MESSAGES[@]}"; do
        unset 'FAILURE_MESSAGES[$key]'
    done

    # Clear error details
    for key in "${!ERROR_STACK_TRACES[@]}"; do
        unset 'ERROR_STACK_TRACES[$key]'
    done
    for key in "${!ERROR_MESSAGES[@]}"; do
        unset 'ERROR_MESSAGES[$key]'
    done

    echo "cleared=true"
    echo "records_cleared=$EXECUTION_RECORD_COUNT"

    return 0
}

# Get total execution statistics
# Usage: get_total_execution_stats
# Returns: Aggregate statistics in flat data format
get_total_execution_stats() {
    local total_suites=0
    local passed_suites=0
    local failed_suites=0
    local error_suites=0
    local total_duration=0

    while IFS='|' read -r rec_suite rec_status rec_duration rec_timestamp; do
        if [[ -n "$rec_suite" ]]; then
            ((total_suites++))
            
            # Calculate total duration
            if [[ -n "$rec_duration" ]]; then
                total_duration=$(echo "$total_duration + $rec_duration" | bc 2>/dev/null || echo "$total_duration")
            fi

            # Count by status
            case "$rec_status" in
                passed) ((passed_suites++)) ;;
                failed) ((failed_suites++)) ;;
                error) ((error_suites++)) ;;
            esac
        fi
    done <<< "$EXECUTION_RECORDS"

    echo "total_suites=$total_suites"
    echo "passed_suites=$passed_suites"
    echo "failed_suites=$failed_suites"
    echo "error_suites=$error_suites"
    echo "total_duration=$total_duration"

    return 0
}

