#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$EUID" -ne 0 ]]; then echo "Please run using sudo bash install.sh" >&2; exit 1; fi
RUN_USER="${SUDO_USER:-}"
if [[ -z "$RUN_USER" || "$RUN_USER" == root ]] || ! id "$RUN_USER" &>/dev/null; then
  echo "Please run sudo bash install.sh from your regular user account, not from a root login." >&2; exit 1
fi
BASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
USER_GROUP="$(id -gn "$RUN_USER")"

echo "Installing ffmpeg, ffprobe, rclone and python3 ..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ffmpeg rclone python3 ca-certificates util-linux unattended-upgrades

install -d -o "$RUN_USER" -g "$USER_GROUP" -m 0700 /var/lib/tapo-timelapse
# v1.3 could write root-owned schedule files when status was run via sudo.
for file in /var/lib/tapo-timelapse/.capture-schedule.json /var/lib/tapo-timelapse/.capture-schedule.lock; do
  if [[ -e "$file" ]]; then
    chown "$RUN_USER:$USER_GROUP" "$file"
    chmod 0600 "$file"
  fi
done
# Back up private configuration before appending missing options.
if [[ -f /etc/tapo-timelapse.conf ]]; then
  install -d -o root -g root -m 0700 /var/backups/tapo-timelapse
  install -o root -g root -m 0600 /etc/tapo-timelapse.conf \
    "/var/backups/tapo-timelapse/tapo-timelapse.conf.pre-v1.4"
fi
# Do not reinterpret historical v1.2 photos as 30-minute recordings.
if [[ -e /var/lib/tapo-timelapse/.monitor-start ]]; then
  SCHEDULE_BASELINE=60
else
  SCHEDULE_BASELINE=30
fi
install -o root -g root -m 0755 "$BASE_DIR/tapo-timelapse" /usr/local/bin/tapo-timelapse
install -o root -g root -m 0755 "$BASE_DIR/tapo-notify" /usr/local/bin/tapo-notify
install -o root -g root -m 0755 "$BASE_DIR/tapo-audit" /usr/local/bin/tapo-audit
install -o root -g root -m 0755 "$BASE_DIR/tapo-schedule" /usr/local/bin/tapo-schedule
install -o root -g root -m 0755 "$BASE_DIR/tapo-health" /usr/local/bin/tapo-health
install -o root -g root -m 0755 "$BASE_DIR/tapo-weekly-reboot" /usr/local/bin/tapo-weekly-reboot
# Only audit days from the first complete UTC day after installation.
if [[ ! -e /var/lib/tapo-timelapse/.monitor-start ]]; then
  date -u -d 'tomorrow' +%F > /var/lib/tapo-timelapse/.monitor-start
  chown "$RUN_USER:$USER_GROUP" /var/lib/tapo-timelapse/.monitor-start
  chmod 0600 /var/lib/tapo-timelapse/.monitor-start
fi
if [[ ! -e /etc/tapo-timelapse.conf ]]; then
  install -o root -g "$USER_GROUP" -m 0640 "$BASE_DIR/tapo-timelapse.conf.example" /etc/tapo-timelapse.conf
  echo "Configuration created (edit placeholders before use)."
else
  echo "Existing configuration preserved (missing options are appended only)."
fi
# Never replace existing camera, OneDrive or SMTP credentials.
# Append missing v1.4 settings only.
for entry in \
  "UPLOAD_AFTER_CAPTURE='yes'" \
  "EMAIL_ON_BOOT='yes'" \
  "HEALTH_FREE_SPACE_PERCENT='20'" \
  "HEALTH_STALE_MINUTES='90'" \
  "UPLOAD_FILE_TIMEOUT_SEC='180'"; do
  key="${entry%%=*}"
  if ! grep -Eq "^[[:space:]]*${key}=" /etc/tapo-timelapse.conf; then
    printf '\n%s\n' "$entry" >> /etc/tapo-timelapse.conf
  fi
done

# Preserve the previous 60-minute schedule when upgrading from v1.2.
# Existing interval history from v1.3 stays unchanged.
sudo -u "$RUN_USER" env DATA_DIR=/var/lib/tapo-timelapse \
  /usr/local/bin/tapo-schedule init "$SCHEDULE_BASELINE"

cat >/etc/systemd/system/tapo-capture.service <<UNIT
[Unit]
Description=Capture one Tapo timelapse frame (UTC)
Wants=network-online.target
After=network-online.target time-sync.target

[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse capture
TimeoutStartSec=15min
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UNIT

cat >/etc/systemd/system/tapo-capture.timer <<'UNIT'
[Unit]
Description=Check timelapse schedule every five minutes (interval from config)
[Timer]
OnCalendar=*-*-* *:00/5:00 UTC
AccuracySec=1s
Persistent=false
Unit=tapo-capture.service
[Install]
WantedBy=timers.target
UNIT

cat >/etc/systemd/system/tapo-upload.service <<UNIT
[Unit]
Description=Securely copy Tapo timelapse photos to OneDrive using rclone
Wants=network-online.target
After=network-online.target time-sync.target

[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse upload
TimeoutStartSec=3h
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UNIT

cat >/etc/systemd/system/tapo-upload.timer <<'UNIT'
[Unit]
Description=Catch up on any pending Tapo OneDrive uploads
[Timer]
OnCalendar=*-*-* *:10:00 UTC
AccuracySec=1min
Persistent=true
Unit=tapo-upload.service
[Install]
WantedBy=timers.target
UNIT

cat >/etc/systemd/system/tapo-audit.service <<UNIT
[Unit]
Description=Audit all expected daily photo slots locally and in OneDrive; email discrepancies
Wants=network-online.target
After=network-online.target time-sync.target
[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse audit
TimeoutStartSec=35min
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UNIT

cat >/etc/systemd/system/tapo-audit.timer <<'UNIT'
[Unit]
Description=Timelapse daily audit at 02:30 UTC
[Timer]
OnCalendar=*-*-* 02:30:00 UTC
AccuracySec=1min
Persistent=true
Unit=tapo-audit.service
[Install]
WantedBy=timers.target
UNIT

cat >/etc/systemd/system/tapo-mail.service <<UNIT
[Unit]
Description=Retry pending SMTP notifications
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse mail-flush
TimeoutStartSec=15min
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UNIT

cat >/etc/systemd/system/tapo-mail.timer <<'UNIT'
[Unit]
Description=Retry SMTP queue every hour
[Timer]
OnCalendar=*-*-* *:25:00 UTC
AccuracySec=1min
Persistent=true
Unit=tapo-mail.service
[Install]
WantedBy=timers.target
UNIT

# Daily package updates: within the current Debian/Raspberry Pi OS
# release only, without automatic distribution upgrades.
# Existing package repositories remain unchanged.
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
cat >/etc/apt/apt.conf.d/52-tapo-timelapse-upgrades <<'APT'
Unattended-Upgrade::Origins-Pattern {
  "origin=Debian,codename=${distro_codename}";
  "origin=Debian,codename=${distro_codename}-updates";
  "origin=Debian,codename=${distro_codename}-security";
  "origin=Raspbian,codename=${distro_codename}";
  "site=archive.raspberrypi.com";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Dependencies "false";
APT
install -d /etc/systemd/system/apt-daily-upgrade.service.d
cat >/etc/systemd/system/apt-daily-upgrade.service.d/90-tapo-low-priority.conf <<'UNIT'
[Service]
Nice=15
IOSchedulingClass=idle
UNIT

cat >/etc/systemd/system/tapo-health.service <<UNIT
[Unit]
Description=Check Tapo timelapse disk, updates and service health
Wants=network-online.target
After=network-online.target time-sync.target
[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse health
TimeoutStartSec=8min
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
UNIT
cat >/etc/systemd/system/tapo-health.timer <<'UNIT'
[Unit]
Description=Hourly Tapo timelapse technical health check
[Timer]
OnCalendar=*-*-* *:12:00 UTC
Persistent=true
AccuracySec=1min
Unit=tapo-health.service
[Install]
WantedBy=timers.target
UNIT

cat >/etc/systemd/system/tapo-boot-notify.service <<UNIT
[Unit]
Description=Tapo timelapse boot notification via SMTP
Wants=network-online.target
After=network-online.target time-sync.target
[Service]
Type=oneshot
User=$RUN_USER
Group=$USER_GROUP
ExecStart=/usr/local/bin/tapo-timelapse boot-notify
TimeoutStartSec=5min
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/tapo-weekly-reboot.service <<'UNIT'
[Unit]
Description=Graceful timelapse reboot (no power cycling)
After=local-fs.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/tapo-weekly-reboot
TimeoutStartSec=15min
UNIT
cat >/etc/systemd/system/tapo-weekly-reboot.timer <<'UNIT'
[Unit]
Description=Graceful weekly Raspberry Pi reboot (Sunday 04:10 UTC)
[Timer]
OnCalendar=Sun *-*-* 04:10:00 UTC
Persistent=false
AccuracySec=1min
Unit=tapo-weekly-reboot.service
[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
systemctl enable --now tapo-capture.timer tapo-upload.timer tapo-audit.timer tapo-mail.timer tapo-health.timer tapo-weekly-reboot.timer
systemctl enable tapo-boot-notify.service

# Reschedule capture and upload timers after upgrading.
systemctl restart tapo-capture.timer tapo-upload.timer

echo
echo "Done. Next steps for user $RUN_USER:"
echo "  1. sudo nano /etc/tapo-timelapse.conf"
echo "  2. rclone config                (create remote named 'onedrive')"
echo "  3. tapo-timelapse probe"
echo "  4. tapo-timelapse test"
echo "  5. Set SMTP credentials in /etc/tapo-timelapse.conf (also after an upgrade if missing)"
echo "  6. tapo-timelapse mail-test"
echo "  7. Capture interval from existing configuration is preserved"
echo "  8. tapo-timelapse status"
echo "  9. sudo unattended-upgrade --dry-run --debug"
echo " 10. systemctl list-timers --all 'tapo-*.timer' 'apt-daily*'"
echo "Logs: journalctl -u tapo-capture.service -u tapo-upload.service -u tapo-audit.service -u tapo-mail.service -u tapo-health.service -n 80 --no-pager"
