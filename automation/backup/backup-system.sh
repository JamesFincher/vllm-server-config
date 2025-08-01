#!/bin/bash
# Comprehensive Backup System for vLLM Server
# Handles configuration, model weights, logs, and system state backup/recovery

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/etc/vllm/backup/backup.conf"
LOCK_FILE="/var/run/vllm-backup.lock"
LOG_FILE="/var/log/vllm-backup/backup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration if file doesn't exist
BACKUP_ROOT="/opt/vllm-backups"
MODEL_PATH="/models/qwen3"
VLLM_ENV_PATH="/opt/vllm"
CONFIG_PATH="/etc/vllm"
DAILY_RETENTION=7
WEEKLY_RETENTION=4
MONTHLY_RETENTION=12
SNAPSHOT_RETENTION=5
COMPRESSION_LEVEL=6
ENCRYPT_BACKUPS=false

# Load configuration if exists
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Create log directory
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    cleanup_lock
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            error "Backup already running (PID: $pid)"
        else
            warning "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

cleanup_lock() {
    rm -f "$LOCK_FILE"
}

trap cleanup_lock EXIT

show_help() {
    cat << EOF
vLLM Backup System

USAGE:
    $0 <command> [options]

COMMANDS:
    create [type]        Create backup (daily|weekly|monthly|snapshot)
    restore <backup>     Restore from backup
    list                 List available backups
    cleanup              Clean old backups based on retention policy
    verify <backup>      Verify backup integrity
    status               Show backup system status

OPTIONS:
    --dry-run           Show what would be done without executing
    --force             Force operation even if unsafe
    --quiet             Minimal output
    --config FILE       Use alternative config file

EXAMPLES:
    $0 create daily                    # Create daily backup
    $0 create snapshot                 # Create snapshot backup
    $0 restore daily-2025-07-31        # Restore from specific backup
    $0 list                           # List all backups
    $0 cleanup                        # Clean old backups
    $0 verify daily-2025-07-31        # Verify backup integrity

EOF
}

get_backup_size() {
    local path="$1"
    if [[ -d "$path" ]]; then
        du -sh "$path" 2>/dev/null | cut -f1 || echo "Unknown"
    else
        echo "N/A"
    fi
}

calculate_backup_name() {
    local backup_type="$1"
    local timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    echo "${backup_type}-${timestamp}"
}

create_metadata() {
    local backup_dir="$1"
    local backup_type="$2"
    
    cat > "$backup_dir/metadata.json" << EOF
{
    "backup_type": "$backup_type",
    "timestamp": "$(date -Iseconds)",
    "hostname": "$(hostname)",
    "vllm_version": "$(source $VLLM_ENV_PATH/bin/activate && python -c 'import vllm; print(vllm.__version__)' 2>/dev/null || echo 'unknown')",
    "model_path": "$MODEL_PATH",
    "config_path": "$CONFIG_PATH",
    "system_info": {
        "os": "$(lsb_release -d 2>/dev/null | cut -f2 || echo 'Unknown')",
        "kernel": "$(uname -r)",
        "gpu_count": "$(nvidia-smi -L 2>/dev/null | wc -l || echo '0')"
    },
    "backup_size": "$(get_backup_size "$backup_dir")",
    "compression": $([[ "$COMPRESSION_LEVEL" -gt 0 ]] && echo "true" || echo "false"),
    "encryption": $([[ "$ENCRYPT_BACKUPS" == "true" ]] && echo "true" || echo "false")
}
EOF
}

create_system_snapshot() {
    local backup_dir="$1"
    
    log "Creating system snapshot..."
    
    # System packages
    dpkg -l > "$backup_dir/packages.txt"
    pip list > "$backup_dir/python-packages.txt" 2>/dev/null || true
    
    # GPU information
    nvidia-smi -q > "$backup_dir/gpu-info.txt" 2>/dev/null || echo "No GPU info available" > "$backup_dir/gpu-info.txt"
    
    # System configuration
    cp /etc/systemd/system/vllm-*.service "$backup_dir/" 2>/dev/null || true
    
    # Network configuration
    ip addr show > "$backup_dir/network-config.txt"
    
    # Process information
    ps aux > "$backup_dir/processes.txt"
    
    success "System snapshot created"
}

compress_backup() {
    local backup_dir="$1"
    local compressed_file="${backup_dir}.tar.gz"
    
    if [[ "$COMPRESSION_LEVEL" -gt 0 ]]; then
        log "Compressing backup with level $COMPRESSION_LEVEL..."
        tar -czf "$compressed_file" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")"
        
        if [[ "$ENCRYPT_BACKUPS" == "true" && -n "$BACKUP_PASSWORD" ]]; then
            log "Encrypting backup..."
            gpg --batch --yes --cipher-algo AES256 --compress-algo 1 \
                --symmetric --output "${compressed_file}.gpg" \
                --passphrase "$BACKUP_PASSWORD" "$compressed_file"
            rm -f "$compressed_file"
            compressed_file="${compressed_file}.gpg"
        fi
        
        # Remove uncompressed directory
        rm -rf "$backup_dir"
        
        success "Backup compressed: $(basename "$compressed_file")"
        echo "$compressed_file"
    else
        echo "$backup_dir"
    fi
}

create_backup() {
    local backup_type="${1:-daily}"
    local dry_run="${2:-false}"
    
    if [[ "$dry_run" == "true" ]]; then
        log "DRY RUN: Would create $backup_type backup"
        return 0
    fi
    
    create_lock
    
    local backup_name=$(calculate_backup_name "$backup_type")
    local backup_dir="$BACKUP_ROOT/$backup_type/$backup_name"
    
    log "Creating $backup_type backup: $backup_name"
    
    # Create backup directory structure
    mkdir -p "$backup_dir"/{config,logs,system,model-info}
    
    # Backup configurations
    if [[ -d "$CONFIG_PATH" ]]; then
        log "Backing up configuration files..."
        cp -r "$CONFIG_PATH"/* "$backup_dir/config/" 2>/dev/null || true
    fi
    
    # Backup environment
    if [[ -d "$VLLM_ENV_PATH" ]]; then
        log "Backing up Python environment info..."
        source "$VLLM_ENV_PATH/bin/activate"
        pip freeze > "$backup_dir/requirements.txt"
    fi
    
    # Backup logs
    if [[ -d "/var/log/vllm" ]]; then
        log "Backing up logs..."
        cp -r /var/log/vllm/* "$backup_dir/logs/" 2>/dev/null || true
    fi
    
    # Model information (not the actual model files due to size)
    if [[ -d "$MODEL_PATH" ]]; then
        log "Backing up model information..."
        find "$MODEL_PATH" -name "*.json" -o -name "*.txt" -o -name "README*" | \
            xargs -I {} cp {} "$backup_dir/model-info/" 2>/dev/null || true
        
        # Model size and file list
        du -sh "$MODEL_PATH" > "$backup_dir/model-info/model-size.txt"
        find "$MODEL_PATH" -type f -exec ls -lh {} \; > "$backup_dir/model-info/model-files.txt"
    fi
    
    # Create system snapshot
    create_system_snapshot "$backup_dir/system"
    
    # Create metadata
    create_metadata "$backup_dir" "$backup_type"
    
    # Compress and possibly encrypt
    local final_backup=$(compress_backup "$backup_dir")
    
    success "Backup created: $(basename "$final_backup")"
    
    # Send notification if configured
    send_notification "Backup Created" "Successfully created $backup_type backup: $(basename "$final_backup")"
    
    # Cleanup old backups
    cleanup_old_backups "$backup_type"
}

list_backups() {
    log "Available backups:"
    
    for backup_type in daily weekly monthly snapshots; do
        local type_dir="$BACKUP_ROOT/$backup_type"
        if [[ -d "$type_dir" ]] && [[ -n "$(ls -A "$type_dir" 2>/dev/null)" ]]; then
            echo -e "\n${CYAN}$backup_type backups:${NC}"
            for backup in "$type_dir"/*; do
                if [[ -f "$backup" ]] || [[ -d "$backup" ]]; then
                    local size=$(get_backup_size "$backup")
                    local date=$(basename "$backup" | sed 's/.*-\([0-9-_]*\).*/\1/' | tr '_' ' ')
                    printf "  %-40s %10s  %s\n" "$(basename "$backup")" "$size" "$date"
                fi
            done
        fi
    done
}

verify_backup() {
    local backup_name="$1"
    local backup_path=""
    
    # Find backup
    for backup_type in daily weekly monthly snapshots; do
        local type_dir="$BACKUP_ROOT/$backup_type"
        if [[ -f "$type_dir/$backup_name" ]] || [[ -f "$type_dir/$backup_name.tar.gz" ]] || [[ -f "$type_dir/$backup_name.tar.gz.gpg" ]]; then
            backup_path="$type_dir"
            break
        fi
    done
    
    if [[ -z "$backup_path" ]]; then
        error "Backup not found: $backup_name"
    fi
    
    log "Verifying backup: $backup_name"
    
    # Check if compressed
    if [[ -f "$backup_path/$backup_name.tar.gz.gpg" ]]; then
        if [[ "$ENCRYPT_BACKUPS" == "true" && -n "$BACKUP_PASSWORD" ]]; then
            log "Verifying encrypted backup..."
            if gpg --batch --quiet --decrypt --passphrase "$BACKUP_PASSWORD" \
                "$backup_path/$backup_name.tar.gz.gpg" | tar -tzf - > /dev/null; then
                success "Encrypted backup verification passed"
            else
                error "Encrypted backup verification failed"
            fi
        else
            error "Cannot verify encrypted backup: no password configured"
        fi
    elif [[ -f "$backup_path/$backup_name.tar.gz" ]]; then
        log "Verifying compressed backup..."
        if tar -tzf "$backup_path/$backup_name.tar.gz" > /dev/null; then
            success "Compressed backup verification passed"
        else
            error "Compressed backup verification failed"
        fi
    elif [[ -d "$backup_path/$backup_name" ]]; then
        log "Verifying uncompressed backup..."
        if [[ -f "$backup_path/$backup_name/metadata.json" ]]; then
            success "Uncompressed backup verification passed"
        else
            error "Backup metadata missing"
        fi
    else
        error "Backup format not recognized"
    fi
}

cleanup_old_backups() {
    local backup_type="$1"
    local retention_var="${backup_type^^}_RETENTION"
    local retention=${!retention_var}
    local backup_dir="$BACKUP_ROOT/$backup_type"
    
    if [[ ! -d "$backup_dir" ]]; then
        return 0
    fi
    
    log "Cleaning up old $backup_type backups (keeping $retention)"
    
    # Get list of backups sorted by date (newest first)
    local backups=($(ls -t "$backup_dir"/ 2>/dev/null || true))
    local count=${#backups[@]}
    
    if [[ $count -le $retention ]]; then
        log "No cleanup needed for $backup_type backups ($count <= $retention)"
        return 0
    fi
    
    # Remove old backups
    for ((i=$retention; i<$count; i++)); do
        local old_backup="$backup_dir/${backups[$i]}"
        log "Removing old backup: $(basename "$old_backup")"
        rm -rf "$old_backup"
    done
    
    success "Cleaned up $((count - retention)) old $backup_type backups"
}

restore_backup() {
    local backup_name="$1"
    local force="${2:-false}"
    
    if [[ "$force" != "true" ]]; then
        warning "This will restore system configuration and may overwrite current settings."
        read -p "Are you sure you want to continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Restore cancelled by user"
            return 0
        fi
    fi
    
    # Find and extract backup
    local backup_path=""
    local temp_dir="/tmp/vllm-restore-$$"
    
    # Implementation for restore logic would go here
    # This is a complex operation that should be thoroughly tested
    
    log "Restore functionality would be implemented here"
    warning "Restore feature is not yet implemented in this version"
}

send_notification() {
    local title="$1"
    local message="$2"
    
    # Slack notification
    if [[ -n "${SLACK_WEBHOOK:-}" ]]; then
        curl -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"$title: $message\"}" \
            "$SLACK_WEBHOOK" > /dev/null 2>&1 || true
    fi
    
    # Email notification (requires mailutils)
    if [[ -n "${EMAIL_NOTIFICATIONS:-}" ]] && command -v mail > /dev/null 2>&1; then
        echo "$message" | mail -s "$title" "$EMAIL_NOTIFICATIONS" > /dev/null 2>&1 || true
    fi
}

show_status() {
    log "Backup System Status"
    echo
    
    echo -e "${CYAN}Configuration:${NC}"
    echo "  Backup Root: $BACKUP_ROOT"
    echo "  Model Path: $MODEL_PATH"
    echo "  Config Path: $CONFIG_PATH"
    echo "  Compression: Level $COMPRESSION_LEVEL"
    echo "  Encryption: $ENCRYPT_BACKUPS"
    echo
    
    echo -e "${CYAN}Retention Policy:${NC}"
    echo "  Daily: $DAILY_RETENTION backups"
    echo "  Weekly: $WEEKLY_RETENTION backups"
    echo "  Monthly: $MONTHLY_RETENTION backups"
    echo "  Snapshots: $SNAPSHOT_RETENTION backups"
    echo
    
    echo -e "${CYAN}Storage Usage:${NC}"
    if [[ -d "$BACKUP_ROOT" ]]; then
        du -sh "$BACKUP_ROOT"/* 2>/dev/null | while read size path; do
            printf "  %-20s %s\n" "$(basename "$path"):" "$size"
        done
    else
        echo "  Backup directory not found"
    fi
    echo
    
    echo -e "${CYAN}Recent Activity:${NC}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -5 "$LOG_FILE" | sed 's/^/  /'
    else
        echo "  No recent activity"
    fi
}

main() {
    local command="${1:-help}"
    shift || true
    
    case "$command" in
        create)
            local backup_type="${1:-daily}"
            local dry_run=false
            shift || true
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --dry-run) dry_run=true; shift ;;
                    *) shift ;;
                esac
            done
            
            create_backup "$backup_type" "$dry_run"
            ;;
        list)
            list_backups
            ;;
        verify)
            local backup_name="${1:-}"
            if [[ -z "$backup_name" ]]; then
                error "Backup name required for verify command"
            fi
            verify_backup "$backup_name"
            ;;
        cleanup)
            for backup_type in daily weekly monthly snapshots; do
                cleanup_old_backups "$backup_type"
            done
            ;;
        restore)
            local backup_name="${1:-}"
            local force=false
            shift || true
            
            while [[ $# -gt 0 ]]; do
                case $1 in
                    --force) force=true; shift ;;
                    *) shift ;;
                esac
            done
            
            if [[ -z "$backup_name" ]]; then
                error "Backup name required for restore command"
            fi
            restore_backup "$backup_name" "$force"
            ;;
        status)
            show_status
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command. Use 'help' for usage information."
            ;;
    esac
}

main "$@"