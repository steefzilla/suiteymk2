#!/usr/bin/env bash

# Dashboard Formatter
# Displays real-time dashboard view of test execution
# Shows suite status, build status, and test counts

# =============================================================================
# Global State for Dashboard
# =============================================================================

# Initialize global state tracking (only once)
if [[ -z "${DASHBOARD_STATE_INITIALIZED:-}" ]]; then
    declare -gA DASHBOARD_SUITE_STATUS 2>/dev/null || declare -A DASHBOARD_SUITE_STATUS
    declare -gA DASHBOARD_SUITE_DURATION 2>/dev/null || declare -A DASHBOARD_SUITE_DURATION
    declare -gA DASHBOARD_SUITE_QUEUED 2>/dev/null || declare -A DASHBOARD_SUITE_QUEUED
    declare -gA DASHBOARD_SUITE_PASSED 2>/dev/null || declare -A DASHBOARD_SUITE_PASSED
    declare -gA DASHBOARD_SUITE_FAILED 2>/dev/null || declare -A DASHBOARD_SUITE_FAILED
    declare -gA DASHBOARD_SUITE_TOTAL 2>/dev/null || declare -A DASHBOARD_SUITE_TOTAL
    declare -gA DASHBOARD_SUITE_ERRORS 2>/dev/null || declare -A DASHBOARD_SUITE_ERRORS
    declare -gA DASHBOARD_SUITE_WARNINGS 2>/dev/null || declare -A DASHBOARD_SUITE_WARNINGS
    declare -gA DASHBOARD_BUILD_STATUS 2>/dev/null || declare -A DASHBOARD_BUILD_STATUS
    DASHBOARD_STATE_INITIALIZED="true"
fi

# Ordered list of suite IDs (pipe-separated)
DASHBOARD_SUITE_ORDER="${DASHBOARD_SUITE_ORDER:-}"

# Dashboard active state
DASHBOARD_ACTIVE="${DASHBOARD_ACTIVE:-}"

# Column widths for consistent formatting
DASHBOARD_COL_SUITE=16
DASHBOARD_COL_STATUS=10
DASHBOARD_COL_TIME=10
DASHBOARD_COL_NUM=6

# =============================================================================
# Dashboard Header Formatting
# =============================================================================

# Format the dashboard header with column titles
# Usage: format_dashboard_header
# Returns: Formatted header line
format_dashboard_header() {
    local header=""
    
    # Build header with proper column widths
    printf "%-${DASHBOARD_COL_SUITE}s %-${DASHBOARD_COL_STATUS}s %-${DASHBOARD_COL_TIME}s |  " \
        "SUITE" "STATUS" "TIME"
    printf "%-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s |  " \
        "QUEUE" "PASS" "FAIL" "TOTAL"
    printf "%-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s\n" \
        "ERR" "WARN"
    
    return 0
}

# =============================================================================
# Dashboard State Management
# =============================================================================

# Initialize dashboard state
# Usage: init_dashboard_state
# Returns: Initialization status
init_dashboard_state() {
    DASHBOARD_SUITE_ORDER=""
    DASHBOARD_ACTIVE="true"
    
    # Clear all suite data
    for key in "${!DASHBOARD_SUITE_STATUS[@]}"; do
        unset 'DASHBOARD_SUITE_STATUS[$key]'
    done
    for key in "${!DASHBOARD_SUITE_DURATION[@]}"; do
        unset 'DASHBOARD_SUITE_DURATION[$key]'
    done
    for key in "${!DASHBOARD_SUITE_QUEUED[@]}"; do
        unset 'DASHBOARD_SUITE_QUEUED[$key]'
    done
    for key in "${!DASHBOARD_SUITE_PASSED[@]}"; do
        unset 'DASHBOARD_SUITE_PASSED[$key]'
    done
    for key in "${!DASHBOARD_SUITE_FAILED[@]}"; do
        unset 'DASHBOARD_SUITE_FAILED[$key]'
    done
    for key in "${!DASHBOARD_SUITE_TOTAL[@]}"; do
        unset 'DASHBOARD_SUITE_TOTAL[$key]'
    done
    for key in "${!DASHBOARD_SUITE_ERRORS[@]}"; do
        unset 'DASHBOARD_SUITE_ERRORS[$key]'
    done
    for key in "${!DASHBOARD_SUITE_WARNINGS[@]}"; do
        unset 'DASHBOARD_SUITE_WARNINGS[$key]'
    done
    for key in "${!DASHBOARD_BUILD_STATUS[@]}"; do
        unset 'DASHBOARD_BUILD_STATUS[$key]'
    done
    
    echo "dashboard_initialized=true"
    
    return 0
}

# Register a suite in the dashboard
# Usage: register_suite <suite_id> <initial_status>
# Returns: Registration status
register_suite() {
    local suite_id="$1"
    local initial_status="${2:-pending}"
    
    # Add to order list if not already present
    if [[ "$DASHBOARD_SUITE_ORDER" != *"|$suite_id|"* ]] && \
       [[ "$DASHBOARD_SUITE_ORDER" != "$suite_id|"* ]] && \
       [[ "$DASHBOARD_SUITE_ORDER" != *"|$suite_id" ]] && \
       [[ "$DASHBOARD_SUITE_ORDER" != "$suite_id" ]]; then
        if [[ -z "$DASHBOARD_SUITE_ORDER" ]]; then
            DASHBOARD_SUITE_ORDER="$suite_id"
        else
            DASHBOARD_SUITE_ORDER="$DASHBOARD_SUITE_ORDER|$suite_id"
        fi
    fi
    
    # Initialize suite data
    DASHBOARD_SUITE_STATUS[$suite_id]="$initial_status"
    DASHBOARD_SUITE_DURATION[$suite_id]="0"
    DASHBOARD_SUITE_QUEUED[$suite_id]="0"
    DASHBOARD_SUITE_PASSED[$suite_id]="0"
    DASHBOARD_SUITE_FAILED[$suite_id]="0"
    DASHBOARD_SUITE_TOTAL[$suite_id]="0"
    DASHBOARD_SUITE_ERRORS[$suite_id]="0"
    DASHBOARD_SUITE_WARNINGS[$suite_id]="0"
    DASHBOARD_BUILD_STATUS[$suite_id]=""
    
    echo "suite_registered=true"
    echo "suite_id=$suite_id"
    echo "initial_status=$initial_status"
    
    return 0
}

# Update suite status
# Usage: update_suite_status <suite_id> <new_status>
# Returns: Update status
update_suite_status() {
    local suite_id="$1"
    local new_status="$2"
    
    # Check if suite exists
    if [[ -z "${DASHBOARD_SUITE_STATUS[$suite_id]+x}" ]]; then
        echo "status_updated=false"
        echo "suite_not_found=true"
        echo "suite_id=$suite_id"
        return 1
    fi
    
    DASHBOARD_SUITE_STATUS[$suite_id]="$new_status"
    
    echo "status_updated=true"
    echo "suite_id=$suite_id"
    echo "new_status=$new_status"
    
    return 0
}

# Get suite status
# Usage: get_suite_status <suite_id>
# Returns: Current status
get_suite_status() {
    local suite_id="$1"
    
    local status="${DASHBOARD_SUITE_STATUS[$suite_id]:-unknown}"
    
    echo "suite_id=$suite_id"
    echo "status=$status"
    
    return 0
}

# Set build status for suite
# Usage: set_build_status <suite_id> <build_status>
# Returns: Status
set_build_status() {
    local suite_id="$1"
    local build_status="$2"
    
    DASHBOARD_BUILD_STATUS[$suite_id]="$build_status"
    
    echo "build_status_set=true"
    echo "suite_id=$suite_id"
    echo "build_status=$build_status"
    
    return 0
}

# Get build status for suite
# Usage: get_build_status <suite_id>
# Returns: Build status
get_build_status() {
    local suite_id="$1"
    
    local build_status="${DASHBOARD_BUILD_STATUS[$suite_id]:-}"
    
    echo "suite_id=$suite_id"
    echo "build_status=$build_status"
    
    return 0
}

# Update suite test counts
# Usage: update_suite_counts <suite_id> <total> <passed> <failed> <errors> <warnings>
# Returns: Update status
update_suite_counts() {
    local suite_id="$1"
    local total="$2"
    local passed="$3"
    local failed="$4"
    local errors="${5:-0}"
    local warnings="${6:-0}"
    
    DASHBOARD_SUITE_TOTAL[$suite_id]="$total"
    DASHBOARD_SUITE_PASSED[$suite_id]="$passed"
    DASHBOARD_SUITE_FAILED[$suite_id]="$failed"
    DASHBOARD_SUITE_ERRORS[$suite_id]="$errors"
    DASHBOARD_SUITE_WARNINGS[$suite_id]="$warnings"
    
    # Calculate queued (total - passed - failed)
    local queued=$((total - passed - failed))
    DASHBOARD_SUITE_QUEUED[$suite_id]="$queued"
    
    echo "counts_updated=true"
    echo "suite_id=$suite_id"
    
    return 0
}

# Get suite test counts
# Usage: get_suite_counts <suite_id>
# Returns: Test counts
get_suite_counts() {
    local suite_id="$1"
    
    echo "suite_id=$suite_id"
    echo "total=${DASHBOARD_SUITE_TOTAL[$suite_id]:-0}"
    echo "passed=${DASHBOARD_SUITE_PASSED[$suite_id]:-0}"
    echo "failed=${DASHBOARD_SUITE_FAILED[$suite_id]:-0}"
    echo "queued=${DASHBOARD_SUITE_QUEUED[$suite_id]:-0}"
    echo "errors=${DASHBOARD_SUITE_ERRORS[$suite_id]:-0}"
    echo "warnings=${DASHBOARD_SUITE_WARNINGS[$suite_id]:-0}"
    
    return 0
}

# Update suite duration
# Usage: update_suite_duration <suite_id> <duration>
# Returns: Update status
update_suite_duration() {
    local suite_id="$1"
    local duration="$2"
    
    DASHBOARD_SUITE_DURATION[$suite_id]="$duration"
    
    echo "duration_updated=true"
    echo "suite_id=$suite_id"
    echo "duration=$duration"
    
    return 0
}

# Get suite duration
# Usage: get_suite_duration <suite_id>
# Returns: Duration
get_suite_duration() {
    local suite_id="$1"
    
    local duration="${DASHBOARD_SUITE_DURATION[$suite_id]:-0}"
    
    echo "suite_id=$suite_id"
    echo "duration=$duration"
    
    return 0
}

# =============================================================================
# Dashboard Formatting Functions
# =============================================================================

# Format status indicator symbol
# Usage: format_status_indicator <status>
# Returns: Formatted status with symbol
format_status_indicator() {
    local status="$1"
    
    case "$status" in
        passed)
            echo "✓ passed"
            ;;
        failed)
            echo "✗ failed"
            ;;
        error)
            echo "⚠ error"
            ;;
        running)
            echo "► running"
            ;;
        pending)
            echo "○ pending"
            ;;
        loading)
            echo "⋯ loading"
            ;;
        building)
            echo "⚙ building"
            ;;
        *)
            echo "? $status"
            ;;
    esac
    
    return 0
}

# Format duration for display
# Usage: format_duration <seconds>
# Returns: Formatted duration string
format_duration() {
    local duration="$1"
    
    if [[ -z "$duration" ]] || [[ "$duration" == "0" ]]; then
        echo "-"
        return 0
    fi
    
    echo "${duration}s"
    
    return 0
}

# Format a single suite row for the dashboard
# Usage: format_suite_row <suite_data>
# Returns: Formatted row
format_suite_row() {
    local suite_data="$1"
    
    # Parse suite data
    local suite_id status duration queued passed failed total errors warnings build_status
    
    suite_id=$(echo "$suite_data" | grep "^suite_id=" | cut -d'=' -f2)
    status=$(echo "$suite_data" | grep "^status=" | cut -d'=' -f2)
    duration=$(echo "$suite_data" | grep "^duration=" | cut -d'=' -f2)
    queued=$(echo "$suite_data" | grep "^queued=" | cut -d'=' -f2)
    passed=$(echo "$suite_data" | grep "^passed=" | cut -d'=' -f2)
    failed=$(echo "$suite_data" | grep "^failed=" | cut -d'=' -f2)
    total=$(echo "$suite_data" | grep "^total=" | cut -d'=' -f2)
    errors=$(echo "$suite_data" | grep "^errors=" | cut -d'=' -f2)
    warnings=$(echo "$suite_data" | grep "^warnings=" | cut -d'=' -f2)
    build_status=$(echo "$suite_data" | grep "^build_status=" | cut -d'=' -f2)
    
    # Truncate long suite names
    local display_name="$suite_id"
    if [[ ${#display_name} -gt $((DASHBOARD_COL_SUITE - 1)) ]]; then
        display_name="${display_name:0:$((DASHBOARD_COL_SUITE - 2))}.."
    fi
    
    # Format duration
    local formatted_duration
    formatted_duration=$(format_duration "$duration")
    
    # Determine display status (include build status if building)
    local display_status="$status"
    if [[ -n "$build_status" ]] && [[ "$build_status" != "built" ]]; then
        display_status="$build_status"
    fi
    
    # Output formatted row
    printf "%-${DASHBOARD_COL_SUITE}s %-${DASHBOARD_COL_STATUS}s %-${DASHBOARD_COL_TIME}s |  " \
        "$display_name" "$display_status" "$formatted_duration"
    printf "%-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s |  " \
        "${queued:-0}" "${passed:-0}" "${failed:-0}" "${total:-0}"
    printf "%-${DASHBOARD_COL_NUM}s %-${DASHBOARD_COL_NUM}s\n" \
        "${errors:-0}" "${warnings:-0}"
    
    return 0
}

# =============================================================================
# Full Dashboard Rendering
# =============================================================================

# Render the complete dashboard
# Usage: render_dashboard
# Returns: Complete dashboard output
render_dashboard() {
    # Print header
    format_dashboard_header
    
    # Print separator
    local separator_width=$((DASHBOARD_COL_SUITE + DASHBOARD_COL_STATUS + DASHBOARD_COL_TIME + 4 + \
                            DASHBOARD_COL_NUM * 4 + 6 + DASHBOARD_COL_NUM * 2 + 2))
    printf '%*s\n' "$separator_width" '' | tr ' ' '-'
    
    # Check if we have any suites
    if [[ -z "$DASHBOARD_SUITE_ORDER" ]]; then
        echo "(no suites registered)"
        return 0
    fi
    
    # Print each suite row
    local IFS='|'
    for suite_id in $DASHBOARD_SUITE_ORDER; do
        if [[ -n "$suite_id" ]]; then
            # Build suite data string
            local suite_data="suite_id=$suite_id
status=${DASHBOARD_SUITE_STATUS[$suite_id]:-pending}
duration=${DASHBOARD_SUITE_DURATION[$suite_id]:-0}
queued=${DASHBOARD_SUITE_QUEUED[$suite_id]:-0}
passed=${DASHBOARD_SUITE_PASSED[$suite_id]:-0}
failed=${DASHBOARD_SUITE_FAILED[$suite_id]:-0}
total=${DASHBOARD_SUITE_TOTAL[$suite_id]:-0}
errors=${DASHBOARD_SUITE_ERRORS[$suite_id]:-0}
warnings=${DASHBOARD_SUITE_WARNINGS[$suite_id]:-0}
build_status=${DASHBOARD_BUILD_STATUS[$suite_id]:-}"
            
            format_suite_row "$suite_data"
        fi
    done
    
    return 0
}

# Get overall dashboard state
# Usage: get_dashboard_state
# Returns: State summary
get_dashboard_state() {
    local total_suites=0
    local suites_passed=0
    local suites_failed=0
    local suites_error=0
    local suites_running=0
    local suites_pending=0
    
    # Count suites by status
    if [[ -n "$DASHBOARD_SUITE_ORDER" ]]; then
        local IFS='|'
        for suite_id in $DASHBOARD_SUITE_ORDER; do
            if [[ -n "$suite_id" ]]; then
                ((total_suites++))
                
                local status="${DASHBOARD_SUITE_STATUS[$suite_id]:-pending}"
                case "$status" in
                    passed) ((suites_passed++)) ;;
                    failed) ((suites_failed++)) ;;
                    error) ((suites_error++)) ;;
                    running|loading) ((suites_running++)) ;;
                    pending) ((suites_pending++)) ;;
                esac
            fi
        done
    fi
    
    echo "total_suites=$total_suites"
    echo "suites_passed=$suites_passed"
    echo "suites_failed=$suites_failed"
    echo "suites_error=$suites_error"
    echo "suites_running=$suites_running"
    echo "suites_pending=$suites_pending"
    echo "dashboard_active=$DASHBOARD_ACTIVE"
    
    return 0
}

# Clear all dashboard state
# Usage: clear_dashboard_state
# Returns: Status
clear_dashboard_state() {
    # Re-initialize to clear everything
    init_dashboard_state >/dev/null 2>&1
    
    echo "dashboard_cleared=true"
    
    return 0
}

