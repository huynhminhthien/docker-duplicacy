#!/bin/bash
# shellcheck disable=SC2317

set -euo pipefail

# Configuration
PRE_BACKUP_SCRIPT=/scripts/pre-backup.sh
POST_BACKUP_SCRIPT=/scripts/post-backup.sh
LOCK_DIR=/var/lock/duplicacy
LOG_DIR=/var/log/duplicacy
BACKUP_LOG=$LOG_DIR/backup.log
PRUNE_LOG=$LOG_DIR/prune.log
COPY_LOG=$LOG_DIR/copy.log
REPO_PATH=/data
GLOBAL_LOCK="$LOCK_DIR/duplicacy.lock"

# Ensure log and lock directories exist
mkdir -p "$LOG_DIR" "$LOCK_DIR"

log() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    local log_file

    case "$level" in
        "BACKUP") log_file="$BACKUP_LOG" ;;
        "PRUNE")  log_file="$PRUNE_LOG" ;;
        "COPY")   log_file="$COPY_LOG" ;;
        *)        log_file="$BACKUP_LOG" ;;
    esac

    echo "$log_entry" | tee -a "$log_file"
}

run_with_logging() {
    local level=$1
    shift
    local cmd=("$@")

    log "$level" "Starting command: ${cmd[*]}"
    log "$level" "=== Command output start ==="

    # Run command and process output in real-time with a process substitution
    # This avoids creating a subshell for the main command
    local status=0
    while IFS= read -r line; do
        log "$level" "$line"
    done < <("${cmd[@]}" 2>&1 || status=$?)

    log "$level" "=== Command output end ==="
    return "$status"
}

# Simple global lock system with file-descriptor locking
acquire_lock() {
    local operation=$1
    
    # Create lock file if it doesn't exist
    touch "$GLOBAL_LOCK"
    
    # Try to acquire an exclusive lock on fd 200
    exec 200>"$GLOBAL_LOCK"
    if ! flock -n 200; then
        log "$operation" "Cannot obtain lock on $GLOBAL_LOCK. Another duplicacy operation is already running."
        exec 200>&-  # Close the file descriptor
        return 1
    fi
    
    # Write current PID and operation to lock file
    echo "$$ - $operation $(date)" >&200
    
    # Keep fd 200 open for the duration of the lock
    return 0
}

release_lock() {
    # Close fd 200, which releases the lock automatically
    exec 200>&- 2>/dev/null || true
}

do_backup() {
    local status=0

    log "BACKUP" "Starting backup"
    
    if [[ -f "$PRE_BACKUP_SCRIPT" ]]; then
        log "BACKUP" "Running pre-backup script"
        run_with_logging "BACKUP" bash "$PRE_BACKUP_SCRIPT"
        status=$?
        if [ "$status" -ne 0 ]; then
            log "BACKUP" "Pre-backup script failed with status $status. Aborting backup."
            return "$status"
        fi
    fi

    run_with_logging "BACKUP" duplicacy backup "${DUPLICACY_BACKUP_OPTIONS:-}"
    status=$?
    if [ "$status" -ne 0 ]; then
        log "BACKUP" "Backup failed with status $status"
    fi

    if [[ -f "$POST_BACKUP_SCRIPT" ]]; then
        log "BACKUP" "Running post-backup script"
        run_with_logging "BACKUP" bash "$POST_BACKUP_SCRIPT" "$status"
        post_status=$?
        if [ "$post_status" -ne 0 ]; then
            log "BACKUP" "Post-backup script failed with status $post_status"
            [[ $status -eq 0 ]] && status=$post_status
        fi
    fi

    log "BACKUP" "Backup completed with status $status"
    return "$status"
}

do_prune() {
    local status=0

    if [[ -n "${DUPLICACY_PRUNE_OPTIONS:-}" ]]; then
        log "PRUNE" "Starting prune operation"
        run_with_logging "PRUNE" duplicacy prune "${DUPLICACY_PRUNE_OPTIONS}"
        status=$?
        if [ "$status" -ne 0 ]; then
            log "PRUNE" "Prune failed with status $status"
            return "$status"
        fi
        log "PRUNE" "Prune completed successfully"
    else
        log "PRUNE" "No prune options set, skipping prune"
    fi

    return "$status"
}

do_copy() {
    local status=0

    if [[ -z "${DUPLICACY_COPY_OPTIONS:-}" ]]; then
        log "COPY" "Error: DUPLICACY_COPY_OPTIONS must be set (e.g., '-from local -to b2')"
        return 1
    fi

    log "COPY" "Starting copy operation"
    log "COPY" "Command: duplicacy copy $DUPLICACY_COPY_OPTIONS"
    run_with_logging "COPY" duplicacy copy "${DUPLICACY_COPY_OPTIONS}"
    status=$?
    if [ "$status" -ne 0 ]; then
        log "COPY" "Copy operation failed with status $status"
        return "$status"
    fi

    log "COPY" "Copy operation completed successfully"
    return "$status"
}

precheck() {
    local level=$1
    
    if [[ ! -f "$REPO_PATH/.duplicacy/preferences" ]]; then
        log "$level" "Duplicacy preference not found at $REPO_PATH/.duplicacy/preferences"
        exit 1
    fi
    cd "$REPO_PATH"
}

# Cleanup function
cleanup() {
    local exit_code=$?
    release_lock
    exit "$exit_code"
}

# Set up trap for script termination
trap cleanup EXIT INT TERM

# Main logic
ARG=$(echo "${1:-}" | tr '[:lower:]' '[:upper:]')

# Acquire global lock first - this ensures only one instance of the script runs
if ! acquire_lock "${1:-UNKNOWN}"; then
    exit 1
fi

precheck "$ARG"

declare -g status=0
case "${1:-}" in
    backup|prune|copy)
        "do_${1}" || status=$?
        ;;
    *)
        log "ERROR" "Invalid command. Usage: $0 <backup|prune|copy>"
        status=1
        ;;
esac

exit $status