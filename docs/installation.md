# Tapo C310 Timelapse v1.4 — Installation and Upgrade

The software is designed for a headless Raspberry Pi 1/2 running **Raspberry Pi OS Lite (32-bit)**. Camera snapshots are captured according to the configured UTC interval and uploaded to OneDrive through rclone. Email monitoring is handled by authenticated SMTP.

## Before you begin

- Back up your SD card and your existing private configuration before changing the installation.
- Use a reliable power supply, an SD card with sufficient space, and a working Ethernet/Wi-Fi connection.
- Enable the Tapo C310's local camera account and ensure its RTSP main stream (`stream1`) is accessible.
- Set the camera's video quality to its maximum 3 MP resolution if available in your firmware/app.
- Sign in as the normal service user (`master` in the original installation). Run the installer with `sudo`, **not** from a root shell.

## Install or upgrade from an existing release

Download this repository or clone it onto the Pi:

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/tapo-c310-timelapse.git
cd tapo-c310-timelapse
sudo bash install.sh
```

If upgrading an existing installation, `cd` to the updated source directory and run the same `sudo bash install.sh` command. It preserves the existing `/etc/tapo-timelapse.conf`, rclone authentication, SMTP settings, recorded photos and capture schedule history. It also repairs ownership of schedule files affected by the v1.3 bug and makes a root-readable backup of the private configuration under `/var/backups/tapo-timelapse/`.

The installer uses `apt-get` to install or update required packages. This may take several minutes on a Raspberry Pi 1.

## Configure the installation

Edit:

```bash
sudo nano /etc/tapo-timelapse.conf
```

Set the camera address and camera-specific credentials, as well as SMTP details. A sanitized example is included in [`tapo-timelapse.conf.example`](../tapo-timelapse.conf.example). **Never publish the actual configuration.**

The key controls are:

```ini
CAPTURE_INTERVAL_MINUTES='20'   # 72 images per full UTC day
UPLOAD_AFTER_CAPTURE='yes'      # Upload each photo once saved
LOCAL_RETENTION_DAYS='14'       # Remove old local originals only after verification
EMAIL_ON_BOOT='yes'             # Email after the Pi boots
HEALTH_FREE_SPACE_PERCENT='20'
HEALTH_STALE_MINUTES='90'
UPLOAD_FILE_TIMEOUT_SEC='180'
```

Supported intervals: **5, 10, 15, 20, 30 or 60 minutes**, aligned to UTC clock boundaries. The example configuration defaults to 30 minutes (48 images/day). Changes are picked up by the five-minute scheduling timer. Historical UTC days retain the intervals that were active at the time.

**Do not change `RCLONE_ROOT` just to translate its name.** The default `Timelapse/Grundstueck` is the existing OneDrive destination. Changing it creates a new location for subsequent uploads.

## Connect OneDrive with rclone

Configure the OneDrive remote under the **service user**, not root:

```bash
rclone config
rclone lsd onedrive:
```

For a headless Pi, establish a local SSH tunnel from Windows to the Pi and then complete rclone's browser flow on Windows:

```powershell
ssh -L 53682:127.0.0.1:53682 master@YOUR_PI_IP
```

Inside that SSH session run `rclone config`; choose browser-based authentication and paste the URL beginning with `http://127.0.0.1:53682/` into your Windows browser. Keep the SSH tunnel open until authorization succeeds. A full `rclone.conf` copied from another computer can also work, provided file permissions and ownership are correct. Protect this file as a secret.

## Verify each part

```bash
tapo-timelapse probe             # Verify RTSP stream and resolution
tapo-timelapse test              # Save a one-off camera test image
tapo-timelapse mail-test         # Send authenticated SMTP test message
tapo-timelapse status            # Show current capture schedule and available space
systemctl list-timers --all 'tapo-*.timer' 'apt-daily*'
```

The production capture timer polls every five minutes and takes a photo only when the configured UTC interval is due. After a successful image, the service uploads **one file at a time**. FFmpeg and rclone share a lock to avoid simultaneous CPU/RAM-heavy operations. A slow ongoing transfer can delay the next capture slightly; the per-file upload timeout limits this.

To follow recent activity:

```bash
sudo journalctl -u tapo-capture.service -n 60 --no-pager
sudo journalctl -u tapo-upload.service -n 60 --no-pager
sudo journalctl -u tapo-audit.service -n 60 --no-pager
sudo journalctl -u tapo-health.service -n 60 --no-pager
```

To trigger an upload catch-up manually:

```bash
sudo systemctl start tapo-upload.service
sudo journalctl -u tapo-upload.service -f
```

## Upload receipts and local files

- Local originals: `/var/lib/tapo-timelapse/YYYY/MM/DD/YYYY-MM-DD_HH-MM-00Z.png`
- Per-file upload receipts: `/var/lib/tapo-timelapse/.uploaded/YYYY/MM/DD/<filename>.ok`
- Remote images: `onedrive:Timelapse/Grundstueck/YYYY/MM/DD/` (default)
- SMTP queue: `/var/lib/tapo-timelapse/.mailqueue/`
- Private config: `/etc/tapo-timelapse.conf`

Upload receipts store a local record of successful uploads and the file size, avoiding needless repeated transfers. They do not continuously prove that a file still exists in OneDrive. The daily audit checks expected time slots remotely, and retention cleanup uses `rclone check` before deleting older local originals. `rclone copyto` is used for uploads; the system is not configured to delete cloud files when local files are removed.

## Monitoring

The daily audit is scheduled at **02:30 UTC** and checks completed UTC days against the historical capture schedule. Missing slots or missing OneDrive files generate SMTP alarms. An hourly health task checks disk free space, image freshness, timer health, failed audit/upgrade services and reboot status. Retryable SMTP messages remain in a local queue if email delivery fails.

```bash
sudo systemctl start tapo-health.service
sudo journalctl -u tapo-health.service -n 30 --no-pager
```

Be aware that a Raspberry Pi that is completely unpowered or offline **cannot alert you immediately**. Independent external heartbeat monitoring is necessary for that use case.

## OS updates and scheduled restart

The installer configures `unattended-upgrades` for stable updates from the currently configured Debian/Raspbian/Raspberry Pi package repositories. It does not automatically upgrade to a new major OS version and does not ask APT to reboot the Pi.

```bash
sudo unattended-upgrade --dry-run --debug
systemctl list-timers --all 'apt-daily*'
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
```

The weekly reboot timer performs a **graceful system reboot** on Sundays at **04:10 UTC**. It avoids rebooting during active media operations or APT upgrades, and attempts to send an SMTP boot notice after the system starts again. Do not intentionally pull the power cord as a regular reboot mechanism: doing so risks SD-card corruption.

## Troubleshooting

If photos stop appearing, look at the capture journal and the schedule file permissions:

```bash
systemctl show tapo-capture.service tapo-audit.service -p User -p Group
sudo ls -l /var/lib/tapo-timelapse/.capture-schedule*
sudo journalctl -u tapo-capture.service -u tapo-audit.service -n 80 --no-pager
```

If a historical root-run command left the schedule files owned by root, upgrade to v1.4 using `sudo bash install.sh` from the normal account. Do not recursively chmod the entire data directory.

For diagnosing OS freezes, enable persistent `systemd-journald` storage, and inspect `journalctl -b -1` following a reboot. The software itself does not guarantee protection against SD-card faults, unstable power or kernel hangs.
