#!/bin/bash

PRE_BACKUP_SCRIPT=/scripts/pre-backup.sh
POST_BACKUP_SCRIPT=/scripts/post-backup.sh
LOCK=/tmp/backup.lock
PRUNE=/tmp/prune.lock

[[ -f "/data/.duplicacy/preferences" ]] || {
  echo "Duplicacy preference not found"
  exit 1
}

cd /data

do_backup() {
  status=0

  if ! mkdir $LOCK 2>/dev/null; then
    echo "Backup is running"
    return
  fi

  if [[ -f "$PRE_BACKUP_SCRIPT" ]]; then
    echo "Running pre-backup script"
    sh "$PRE_BACKUP_SCRIPT" 2>&1 | tee /tmp/backup.log
    status="${PIPESTATUS[0]}"
  fi

  if [[ "$status" != 0 ]]; then
    echo "Pre-backup script exited with status code $status. Not performing backup." >&2
    rmdir $LOCK
    return
  fi

  echo "Backing up $(date)"
  duplicacy backup $DUPLICACY_BACKUP_OPTIONS 2>&1 | tee -a /tmp/backup.log
  status="${PIPESTATUS[0]}"

  if [[ -f "$POST_BACKUP_SCRIPT" ]]; then
    echo "Running post-backup script"
    sh "$POST_BACKUP_SCRIPT" "$status" | tee -a /tmp/backup.log
    status="${PIPESTATUS[0]}"
    echo "Post-backup script exited with status $status"
  fi
  rmdir $LOCK
}

do_prune() {
  if ! mkdir $PRUNE 2>/dev/null; then
    echo "Prune is running"
    return
  fi
  if [[ ! -z "$DUPLICACY_PRUNE_OPTIONS" ]]; then
    echo "Prunning $(date)"
    duplicacy -log prune $DUPLICACY_PRUNE_OPTIONS
  fi
  rmdir $PRUNE
}

case "$1" in
  backup)
    do_backup
    ;;
  prune)
    do_prune
    ;;
  *)
    echo "Invalid command, usage: $0 <backup|prune> "
esac
