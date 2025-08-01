#!/bin/bash
# Backup System Deployment Script
# Deploys comprehensive backup and recovery automation for vLLM server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE=""
BACKUP_ROOT="/opt/vllm-backups"
LOG_FILE="/var/log/vllm-deployment/backup-deployment.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [BACKUP]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

if [[ -z "$CONFIG_FILE" ]]; then
    error "Configuration file required. Use --config"
fi

# Source configuration
source "$CONFIG_FILE"

log "Deploying backup system..."

# Create backup directories
mkdir -p "$BACKUP_ROOT"/{daily,weekly,monthly,snapshots,config,logs}
mkdir -p /etc/vllm/backup

# Create backup configuration
cat > /etc/vllm/backup/backup.conf << EOF
# vLLM Backup Configuration
BACKUP_ROOT="$BACKUP_ROOT"
MODEL_PATH="$MODEL_PATH"
VLLM_ENV_PATH="$VLLM_ENV_PATH"
CONFIG_PATH="/etc/vllm"

# Retention policies
DAILY_RETENTION=7
WEEKLY_RETENTION=4  
MONTHLY_RETENTION=12
SNAPSHOT_RETENTION=5

# Backup destinations
LOCAL_BACKUP=true
REMOTE_BACKUP=false
S3_BUCKET=""
REMOTE_HOST=""

# Compression
COMPRESSION_LEVEL=6
ENCRYPT_BACKUPS=true
BACKUP_PASSWORD=""

# Notifications
SLACK_WEBHOOK=""
EMAIL_NOTIFICATIONS=""
EOF

success "Backup configuration created"

# Install backup system script
cp "$SCRIPT_DIR/backup-system.sh" /usr/local/bin/vllm-backup
chmod +x /usr/local/bin/vllm-backup

# Create systemd timer for automatic backups
cat > /etc/systemd/system/vllm-backup-daily.service << EOF
[Unit]
Description=vLLM Daily Backup
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/vllm-backup create daily
EOF

cat > /etc/systemd/system/vllm-backup-daily.timer << EOF
[Unit]
Description=Run vLLM daily backup
Requires=vllm-backup-daily.service

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Weekly backup timer
cat > /etc/systemd/system/vllm-backup-weekly.service << EOF
[Unit]
Description=vLLM Weekly Backup
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/vllm-backup create weekly
EOF

cat > /etc/systemd/system/vllm-backup-weekly.timer << EOF
[Unit]
Description=Run vLLM weekly backup
Requires=vllm-backup-weekly.service

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Monthly backup timer
cat > /etc/systemd/system/vllm-backup-monthly.service << EOF
[Unit]
Description=vLLM Monthly Backup
After=network.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/bin/vllm-backup create monthly
EOF

cat > /etc/systemd/system/vllm-backup-monthly.timer << EOF
[Unit]
Description=Run vLLM monthly backup
Requires=vllm-backup-monthly.service

[Timer]
OnCalendar=monthly
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable and start timers
systemctl daemon-reload
systemctl enable vllm-backup-daily.timer
systemctl enable vllm-backup-weekly.timer
systemctl enable vllm-backup-monthly.timer
systemctl start vllm-backup-daily.timer
systemctl start vllm-backup-weekly.timer
systemctl start vllm-backup-monthly.timer

# Create initial backup
log "Creating initial snapshot backup..."
/usr/local/bin/vllm-backup create snapshot

# Create backup management wrapper script
cat > /usr/local/bin/vllm-backup-manager << 'EOF'
#!/bin/bash
# vLLM Backup Management Wrapper

case "$1" in
    "dashboard")
        echo "=== vLLM Backup Dashboard ==="
        /usr/local/bin/vllm-backup status
        echo
        /usr/local/bin/vllm-backup list
        ;;
    "emergency-backup")
        echo "Creating emergency backup..."
        /usr/local/bin/vllm-backup create snapshot
        ;;
    *)
        /usr/local/bin/vllm-backup "$@"
        ;;
esac
EOF

chmod +x /usr/local/bin/vllm-backup-manager

success "Backup system deployed successfully"
log "Commands available:"
log "  - vllm-backup: Main backup tool"
log "  - vllm-backup-manager dashboard: Show backup status"
log "  - vllm-backup-manager emergency-backup: Create emergency backup"