# Tapo C310 Timelapse on Raspberry Pi

Headless construction-site timelapse using a **TP-Link Tapo C310**, an older **Raspberry Pi 1/2**, **rclone + Microsoft OneDrive**, and authenticated **SMTP alerting**.

This repository contains the **v1.4 release used on a Raspberry Pi 1**. It has been tested on one real deployment, but is **not a broadly validated, independently security-audited, or commercially supported product**. Review the scripts and back up your Pi before installing.

## AI-generated code disclosure

**Transparency notice:** Most of the source code, installation scripts, documentation, and tests in this repository were generated with assistance from **OpenAI ChatGPT** through an iterative, prompt-driven development process (sometimes called *vibe coding*).

The project owner supplied the functional requirements, operational context, feedback, and results from testing the software on an actual Raspberry Pi with a Tapo C310, OneDrive, and SMTP. ChatGPT drafted and revised the implementation in response to that feedback.

**AI-generated code can contain bugs, security weaknesses, and incorrect assumptions.** Passing automated tests and running successfully on one device does not establish that the project is secure or reliable for every environment. Anyone deploying or contributing to the project should review the code, protect credentials, and test it in their own setup.


## What it does

- Captures the Tapo C310 **RTSP main stream** (`stream1`) at up to **2304 × 1296**, saving a full-resolution **PNG** snapshot (or optional JPEG).
- Uses a configurable interval of **5, 10, 15, 20, 30 or 60 minutes** aligned to UTC time slots. For example, `20` means **72 snapshots per full UTC day**.
- Saves the photo locally, then uploads it to OneDrive via **rclone**, one file at a time. Image capture and cloud transfer share a filesystem lock so resource-heavy steps do not run simultaneously.
- Catches up on files that could not upload, keeps local `.uploaded/` receipts, and runs a daily audit of expected slots and OneDrive files.
- Sends authenticated SMTP warnings about missing photos, upload discrepancies, technical monitor failures, storage capacity and pending reboots.
- Installs **unattended stable OS package updates** and schedules a **graceful weekly reboot** (Sunday, 04:10 UTC), not a forced power cycle.
- Retains local photos for the configured period (default 14 days), and cleans up only following cloud verification.

> **Power loss:** The Pi cannot send email while powered off. Do not routinely unplug it to reboot: hard power cycles can corrupt an SD card. The software's weekly systemd timer performs an orderly reboot. External heartbeat monitoring is required to detect a fully offline Pi in real time.

## Requirements

- Raspberry Pi OS Lite **32-bit** on a Raspberry Pi 1 or 2, networking and SSH configured.
- TP-Link Tapo C310 reachable on the LAN, with a **camera account** (different from the Tapo cloud login) and RTSP enabled/available.
- OneDrive account with sufficient capacity; rclone configured **for the Linux user running the services**.
- SMTP host, port, sender, recipient and username/password (prefer an app password).
- Stable power and a good-quality SD card. A 32 GB card is generally sufficient for the default local retention; actual usage depends on snapshot size and frequency.

## Installation

```bash
# Replace YOUR_GITHUB_USERNAME once the repository has been created.
git clone https://github.com/YOUR_GITHUB_USERNAME/tapo-c310-timelapse.git
cd tapo-c310-timelapse
sudo bash install.sh
```

The installer must be called via `sudo` from your normal Pi user (e.g. `master`), **not as a root login**. It installs required dependencies and systemd units. Existing configuration and photos are retained on upgrades. See **[English installation & upgrade guide](docs/installation.md)** for full details and testing commands.

1. Configure camera, SMTP and the capture interval:

   ```bash
   sudo nano /etc/tapo-timelapse.conf
   ```

   Example values (not real passwords):

   ```ini
   CAMERA_HOST='192.168.1.100'
   CAMERA_USER='camera_account'
   CAMERA_PASSWORD='CHANGE_ME'
   CAPTURE_INTERVAL_MINUTES='20'
   RCLONE_REMOTE='onedrive'
   RCLONE_ROOT='Timelapse/Grundstueck'
   UPLOAD_AFTER_CAPTURE='yes'
   MONITOR_EMAIL_ENABLED='yes'
   SMTP_HOST='smtp.example.com'
   SMTP_PORT='587'
   SMTP_SECURITY='starttls'
   SMTP_USER='camera@example.com'
   SMTP_PASSWORD='CHANGE_ME'
   SMTP_FROM='camera@example.com'
   SMTP_TO='you@example.com'
   ```

2. Configure `rclone config` under the same Linux user that installed the service; name the OneDrive remote `onedrive`, or update `RCLONE_REMOTE`.
3. Test without waiting for the next hour:

   ```bash
   tapo-timelapse probe
   tapo-timelapse test
   tapo-timelapse mail-test
   tapo-timelapse status
   ```

4. Watch the actual timed capture + upload:

   ```bash
   sudo journalctl -u tapo-capture.service -n 60 --no-pager
   sudo journalctl -u tapo-upload.service -n 60 --no-pager
   ```

## File locations

| Purpose | Path |
| --- | --- |
| Private configuration | `/etc/tapo-timelapse.conf` |
| Local photographs | `/var/lib/tapo-timelapse/YYYY/MM/DD/` |
| Per-file upload receipts | `/var/lib/tapo-timelapse/.uploaded/` |
| SMTP queue | `/var/lib/tapo-timelapse/.mailqueue/` |
| Remote images | `onedrive:Timelapse/Grundstueck/YYYY/MM/DD/` (existing default) |
| systemd logs | `journalctl -u tapo-capture.service -u tapo-upload.service` |

Do **not** commit actual configuration files, `rclone.conf`, upload receipts or PNGs to Git.

## Maintenance

```bash
# Check capture/health/upgrade/reboot timers
systemctl list-timers --all 'tapo-*.timer' 'apt-daily*'

# Manually retry pending cloud uploads
sudo systemctl start tapo-upload.service

# Run system health check
sudo systemctl start tapo-health.service
sudo journalctl -u tapo-health.service -n 40 --no-pager

# Verify unattended-upgrades configuration (dry run, no install)
sudo unattended-upgrade --dry-run --debug
```

The weekly reboot timer is independent of APT updates; it waits for active photo/upload work. Upgrades to new OS major releases and new versions of this repository are **not** installed automatically.

## Source layout

```text
install.sh                    # Installer and systemd/apt timer setup
tapo-timelapse               # Capture, upload, audit, status and commands
tapo-schedule                # UTC schedule & interval history (Python)
tapo-audit                   # Daily completeness verification
tapo-notify                  # Authenticated SMTP queue
tapo-health                  # Health and update checks
tapo-weekly-reboot           # Controlled reboot
tapo-timelapse.conf.example  # Example configuration with placeholders
docs/                        # English guide, changelogs and blog article
tests/                       # Offline smoke tests (no camera needed)
.github/workflows/           # Automated syntax/smoke checks
```

## Testing and troubleshooting

Run local checks without a Raspberry Pi:

```bash
bash -n install.sh tapo-timelapse tapo-weekly-reboot
python3 -m unittest discover -s tests -v
```

This does not replace an end-to-end test with a real camera, OneDrive and SMTP account.

**Known limitations:** A watchdog or email sent by the Pi itself cannot detect an outage if the Pi is fully offline; a very slow ongoing transfer may delay an image; camera RTSP resolution depends on the camera's quality settings. The daily auditor intentionally distinguishes expected time slots from the number of files present.

## Documentation and article

- [English installation guide](docs/installation.md)
- [Technical changelog (v1.4)](docs/changelog-v1.4.md)
- [English construction-timelapse tutorial](docs/blog-post-gentz-cloud.md)

## License

**No license selected yet.** Until the owner adds an explicit license, the code is available to view but should not be presumed to grant permission for redistribution or modification. If the goal is public reuse, consider adding an [MIT license](https://choosealicense.com/licenses/mit/) after choosing the copyright holder. See [docs/publishing.md](docs/publishing.md).
