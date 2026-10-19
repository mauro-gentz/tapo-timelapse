# How I Built a Fully Automated Construction Timelapse with a Tapo C310, Raspberry Pi and OneDrive

*An old Raspberry Pi, a 3 MP security camera, and a few lightweight scripts now document our house-building project in Portugal—one photo every 20 minutes, with automatic cloud backups and email alerts.*

When planning the construction of our house, I wanted a record of the progress from the first day to the finished building. I didn't want to store continuous video for months, and I certainly didn't want to retrieve an SD card every few days.

I already had a **TP-Link Tapo C310** overlooking the plot and an old **Raspberry Pi 1** that was doing nothing useful. The result is a small, headless timelapse system that captures a full-resolution frame, saves it locally, transfers it to **Microsoft OneDrive**, and alerts me by email if something goes wrong. I can leave the Pi running without a monitor, keyboard or desktop environment.

This article explains the complete setup using **version 1.4 of my scripts**, including the improvements I made after the first few days of real operation.

> **Project at a glance:** Tapo C310 (2304 × 1296), Raspberry Pi OS Lite 32-bit, FFmpeg, rclone, authenticated SMTP, automatic Linux updates and systemd timers. My capture interval is 20 minutes, giving **72 images per complete UTC day**.

## How it works

```text
Tapo C310 (RTSP /stream1, 3 MP)
              |
              v
Raspberry Pi 1 + Raspberry Pi OS Lite (32-bit)
              |
       Every 20 minutes, UTC
              |
        FFmpeg saves PNG
              |
        32 GB SD card
              |
     rclone uploads ONE image
              |
              v
       Microsoft OneDrive

Independent checks:
- Hourly catch-up upload for files not yet transferred
- Daily audit of the expected images in OneDrive
- SMTP alerts and an hourly health check
- Daily unattended OS updates
- Clean reboot every Sunday
```

The important design choice is **sequential processing**: the Pi doesn't have to decode a camera image and transfer another file to OneDrive at the same time. Each task shares a lock, and rclone handles one image at a time. The actual capture can start a little late if a transfer is already finishing, but the timestamped slot is still preserved.

## What you need

- **TP-Link Tapo C310**, configured for its highest-quality **2304 × 1296** video stream.
- **Raspberry Pi 1 (512 MB)**, Raspberry Pi 2 or newer. I use a Pi 1, so low resource consumption matters.
- **32 GB SD card**; an endurance-rated card and a good power supply are preferable.
- A network connection between Pi and camera. Ethernet is preferable when available.
- **Raspberry Pi OS Lite (32-bit)**, with SSH enabled.
- A **Microsoft OneDrive** account and an SMTP server that supports authentication and TLS.

The camera's `/stream1` is a compressed H.264 video stream. The PNG is a losslessly stored **decoded video frame**, not an uncompressed photograph straight from the sensor. PNG avoids another lossy conversion, but it cannot recover detail already removed by the camera's video encoder.

## 1. Install Raspberry Pi OS Lite

Flash Raspberry Pi OS Lite (32-bit) using [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Configure the hostname, a regular user, SSH and network access before first boot. The commands below assume a Linux user named `timelapse` and a hostname of `timelapse-pi`; replace them with your own values.

Connect from Windows PowerShell:

```powershell
ssh timelapse@timelapse-pi.local
```

Update the base system and verify time synchronization:

```bash
sudo apt update
sudo apt full-upgrade
sudo reboot
# Reconnect after reboot:
timedatectl status
```

Time synchronization should report `System clock synchronized: yes`. My old Pi has no battery-backed real-time clock, so NTP matters: all filenames and capture schedules are based on **UTC**. UTC also avoids duplicated or skipped local clock times when daylight saving time changes.

## 2. Configure the Tapo camera

Open the **Tapo app**, select the C310, and create a separate **Camera Account** in its advanced settings. This is not the same as your TP-Link cloud login. Then set the camera's **Video Quality** to the highest available quality and reserve a stable LAN IP address in your router.

For the C310, TP-Link confirms that the actual resolution of `/stream1` depends on the video-quality selection in the app. The high-resolution RTSP endpoint is:

```text
rtsp://CAMERA_USER:CAMERA_PASSWORD@CAMERA_IP:554/stream1
```

The installer stores the camera credentials in a protected configuration file; there is no need to expose the RTSP stream to the internet or paste the password into a shell command. See [TP-Link's RTSP setup guide](https://www.tp-link.com/pt/support/faq/2680/).

## 3. Install the timelapse package (v1.4)

I packaged the capture, uploading and monitoring logic into a small installer. **[Download the timelapse package v1.4](INSERT_PUBLIC_DOWNLOAD_URL_HERE)**, then copy the ZIP to the Pi. From Windows PowerShell:

```powershell
scp .\tapo-pi2-timelapse-c310-v1.4.zip timelapse@timelapse-pi.local:/home/timelapse/
```

On the Pi, while logged in as your **regular user** (not directly as `root`):

```bash
sudo apt install -y unzip
cd ~
unzip tapo-pi2-timelapse-c310-v1.4.zip
cd tapo-pi2-timelapse-c310-v1.4
sudo bash install.sh
```

The installer uses the account invoking `sudo` as its service user. It installs FFmpeg, rclone, Python 3, unattended-upgrades and systemd service/timer definitions. The relevant paths are:

```text
/etc/tapo-timelapse.conf           Configuration and SMTP credentials
/usr/local/bin/tapo-timelapse     Main command
/var/lib/tapo-timelapse/          Images, state and receipts
/etc/systemd/system/tapo-*.timer  Scheduled jobs
```

**Upgrading an existing installation?** Run the new installer in the same way, from the same regular user. Version 1.4 preserves the existing camera settings, rclone authentication, SMTP configuration and images, and backs up the configuration. It also fixes the ownership issue that affected an earlier version's capture schedule.

## 4. Set the interval and image quality in one config file

All everyday settings live in:

```bash
sudo nano /etc/tapo-timelapse.conf
```

For my 20-minute setup, the relevant entries are:

```ini
CAMERA_HOST='192.168.1.100'
CAMERA_PORT='554'
CAMERA_USER='YOUR_CAMERA_ACCOUNT'
CAMERA_PASSWORD='YOUR_CAMERA_PASSWORD'
CAMERA_STREAM='stream1'

EXPECTED_WIDTH='2304'
EXPECTED_HEIGHT='1296'
IMAGE_FORMAT='png'
CAPTURE_INTERVAL_MINUTES='20'

RCLONE_REMOTE='onedrive'
RCLONE_ROOT='Timelapse/Construction'
RCLONE_CHUNK_SIZE='5Mi'
UPLOAD_AFTER_CAPTURE='yes'
LOCAL_RETENTION_DAYS='14'
```

Replace the addresses, user names, passwords and destination path. The package's example config defaults to **30 minutes** (48 images per UTC day), so explicitly set `CAPTURE_INTERVAL_MINUTES='20'` for **72 images per day**. The supported interval values are **5, 10, 15, 20, 30 or 60 minutes**. The capture timer wakes up every five minutes, and the script decides whether an image is due.

For example:

| Interval | Expected images per complete UTC day |
| --- | ---: |
| 60 minutes | 24 |
| 30 minutes | 48 |
| **20 minutes** | **72** |
| 15 minutes | 96 |

The schedule is tied to UTC clock times, not the last reboot: at 20 minutes, the target times are `00:00`, `00:20`, `00:40`, `01:00` and so on. Changing the interval in the config does not require reinstalling the package. The monitoring remembers the historical interval changes so it doesn't falsely expect 72 images on days when you previously used hourly captures.

Test the camera and its actual delivered resolution:

```bash
tapo-timelapse probe
tapo-timelapse test
```

The `probe` result should contain `width=2304` and `height=1296`. The `test` command saves a separate temporary PNG in `/tmp`; it is **not** a scheduled timelapse image and may not remain there indefinitely.

## 5. Connect Microsoft OneDrive with rclone

Create the OneDrive remote **as the regular Pi user**, because that is also the account used by the systemd services:

```bash
rclone config
```

Give the remote the name `onedrive`. Since my Pi has no desktop, I used an **SSH tunnel to authenticate with the Windows browser** instead of copying a long OAuth token.

Open a new PowerShell session on Windows:

```powershell
ssh -L 53682:127.0.0.1:53682 timelapse@timelapse-pi.local
```

Run `rclone config` inside this SSH session and select automatic browser authentication. When rclone shows a URL such as `http://127.0.0.1:53682/auth?...`, open **the complete URL shown in the terminal** in your Windows browser. The SSH tunnel securely forwards that local port to rclone on the Pi. Finish the Microsoft sign-in, select your drive, save the remote, then check:

```bash
rclone lsd onedrive:
```

This approach is explained in [rclone's remote setup documentation](https://rclone.org/remote_setup/). Keep the rclone configuration private: it holds tokens granting OneDrive access.

## 6. Upload each photograph immediately—with a safety net

Version 1.4 saves a photo locally first, then uploads it immediately via `rclone copyto`. I kept resource usage low with **one transfer, one checker, no multithreaded upload and a small buffer**. FFmpeg and rclone share an exclusive lock, so the heavy capture and transfer steps do not run simultaneously.

Here is what a successful capture looked like on my Pi:

```text
08:40:02  Capturing frame
08:40:28  PNG saved (about 7.8 MB)
08:40:29  OneDrive upload started
08:41:05  OneDrive upload successful
```

If OneDrive is temporarily unavailable, the PNG stays on the SD card. A separate **hourly catch-up upload at minute 10 UTC** checks outstanding photos, including those from the current day. To start that job manually:

```bash
sudo systemctl start tapo-upload.service
sudo journalctl -u tapo-upload.service -n 50 --no-pager
```

Successful transfers get a small local `.ok` receipt, containing the file size:

```text
/var/lib/tapo-timelapse/.uploaded/2026/10/19/
    2026-10-19_07-40-00Z.png.ok
```

The receipt helps skip files that have already been transferred. **It is not proof that the file still exists in OneDrive forever**: if someone manually deletes a cloud file later, the receipt alone will not detect it. The independent daily audit checks the actual cloud listing; older local files are deleted only after a successful remote size comparison.

**Do not delete `.ok` files manually.** The directory begins with a dot, so it is hidden by default in many Linux file browsers and may need **Show hidden files** enabled in WinSCP.

## 7. SMTP alerts and health monitoring

I wanted the system to tell me when something breaks, rather than send an email after every successful photo. Configure authenticated SMTP in `/etc/tapo-timelapse.conf`:

```ini
MONITOR_EMAIL_ENABLED='yes'
MONITOR_LOOKBACK_DAYS='7'
SMTP_HOST='smtp.example.com'
SMTP_PORT='587'
SMTP_SECURITY='starttls'
SMTP_USER='timelapse@example.com'
SMTP_PASSWORD='YOUR_APP_PASSWORD'
SMTP_FROM='timelapse@example.com'
SMTP_TO='your-address@example.com'

EMAIL_ON_BOOT='yes'
HEALTH_FREE_SPACE_PERCENT='20'
HEALTH_STALE_MINUTES='90'
```

If your provider uses implicit TLS on port 465, configure `SMTP_SECURITY='ssl'` and `SMTP_PORT='465'` instead. Send a test email:

```bash
tapo-timelapse mail-test
```

The monitoring has two complementary parts:

- The **daily audit at 02:30 UTC** compares the expected UTC image slots against local files and the OneDrive folder, for up to seven previous days. An incomplete day triggers a detailed email listing missing times. The first partial installation day is excluded, and historical interval changes are accounted for.
- The **hourly health check** detects prolonged absence of fresh photos (90 minutes by default), low SD-card space (below 20% free), inactive key timers and certain failed audit, update or reboot services. It also reports when an OS update has left the standard reboot-required marker.

Upload failures and camera capture failures also generate warnings. Queued emails are retried hourly if the SMTP server is temporarily unavailable, and a boot confirmation is enabled by default. The normal system is otherwise mostly silent; version 1.4 does **not** produce a daily success-summary email.

A lesson from my first days of testing: the old audit once failed due to incorrect permissions on the schedule file. A successfully running SMTP service alone cannot guarantee an audit has completed. The newer health check looks for certain audit failures, and the 1.4 installer repairs the earlier ownership issue.

**Limitation:** If the Raspberry Pi is completely powered off, locked up, or disconnected from the network, it cannot email you at that moment. Only an external heartbeat monitor can raise an alert while the Pi itself is unreachable.

## 8. Automatic OS updates and a safe weekly reboot

I also wanted the Pi to remain maintained without having to visit the building plot just to update it. Version 1.4 installs and configures **unattended-upgrades** for packages from the configured Debian/Raspbian/Raspberry Pi repositories within the current OS release. It does **not** automatically move to a new Debian major version, and it does not automatically upgrade the timelapse script itself.

The APT timers run automatically. Package updates receive reduced CPU and disk-I/O priority to minimize interference with image capture, although a major package installation can still slow down an old Pi. APT-triggered automatic reboots are disabled.

Instead, Linux attempts a **clean reboot every Sunday at 04:10 UTC**. The reboot service waits for an ongoing capture/transfer, and skips rebooting if an APT upgrade is running or activity cannot finish in time. After a successful boot, the Pi queues a status email. This is very different from simply cutting its power: unplugging can corrupt the SD card and should only be an emergency measure.

Inspect the update timers and simulate an update without installing anything:

```bash
systemctl list-timers --all 'apt-daily*'
sudo unattended-upgrade --dry-run --debug
```

For actual update logs:

```bash
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
sudo journalctl -u apt-daily-upgrade.service -n 50 --no-pager
```

A dry run may print `All upgrades installed` even though **no real packages were installed**. That message refers to the simulation.

## 9. Timers, folders and troubleshooting

The installation uses six Timelapse timers plus Debian's APT timers:

| Timer | Function |
| --- | --- |
| `tapo-capture.timer` | Check every five minutes; take photos in configured slots |
| `tapo-upload.timer` | Catch up on outstanding uploads at XX:10 UTC |
| `tapo-audit.timer` | Audit completed days at 02:30 UTC |
| `tapo-mail.timer` | Retry queued email at XX:25 UTC |
| `tapo-health.timer` | Run hourly checks at XX:12 UTC |
| `tapo-weekly-reboot.timer` | Attempt clean Sunday reboot at 04:10 UTC |

Useful commands:

```bash
# Current count, storage and timers
tapo-timelapse status
systemctl list-timers --all 'tapo-*.timer' 'apt-daily*'

# Capture and upload history
sudo journalctl -u tapo-capture.service -u tapo-upload.service -n 80 --no-pager

# Monitor and email history
sudo journalctl -u tapo-audit.service -u tapo-health.service \
  -u tapo-mail.service -n 80 --no-pager

# Run an immediate health check
sudo systemctl start tapo-health.service
sudo journalctl -u tapo-health.service -n 20 --no-pager
```

Photos are organised in the same date folders locally and in OneDrive:

```text
/var/lib/tapo-timelapse/2026/10/19/
    2026-10-19_07-00-00Z.png
    2026-10-19_07-20-00Z.png
    2026-10-19_07-40-00Z.png

OneDrive/Timelapse/Construction/2026/10/19/
    (same filenames)
```

The names always refer to **UTC**, not local Portuguese time. If using WinSCP, connect with your normal Pi user via SFTP and browse `/var/lib/tapo-timelapse/`. Temporary test pictures are under `/tmp`, not in the daily archive, and might be removed.

You can count local images by day with:

```bash
find /var/lib/tapo-timelapse -type f -name '*.png' \
  | sed 's|/[^/]*$||' | sort | uniq -c
```

If you want persistent crash logs on an old Pi, I recommend a size-limited systemd journal:

```bash
sudo mkdir -p /etc/systemd/journald.conf.d /var/log/journal
sudo tee /etc/systemd/journald.conf.d/99-timelapse.conf >/dev/null <<'JOURNAL'
[Journal]
Storage=persistent
SystemMaxUse=100M
SystemMaxFileSize=10M
Compress=yes
JOURNAL
sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
sudo journalctl --flush
```

That journal is limited to approximately 100 MiB, rather than filling the SD card with systemd logs. It does not impose a limit on all other system log files. After a subsequent reboot, `sudo journalctl -b -1` can display the preceding boot's logs.

## 10. Storage planning for a long build

My C310's PNG files are often around **7–10 MB** each. At a 20-minute interval, the numbers add up:

| Time period | Images | At 10 MB per image |
| --- | ---: | ---: |
| One day | 72 | 720 MB |
| 14 days locally | 1,008 | 10.08 GB |
| 30 days | 2,160 | 21.6 GB |
| One year (365 days) | 26,280 | **262.8 GB** |

Actual files can be smaller or larger depending on lighting, weather and scene complexity. A 32 GB SD card is sufficient for my normal **14-day retention**, but the system must still be able to buffer photos during a longer internet outage. The health check alerts me when free space drops below the configured threshold.

The cleanup process uses **`rclone check` with size comparison** before removing older local images. The OneDrive copies are not removed by this local cleanup. File-size verification is useful, but it is not a cryptographic integrity check.

## Final thoughts

This little setup now performs the repetitive work without much attention from me. Each frame is taken at a predictable UTC time, transferred soon afterwards, and checked again by an independent daily audit. It also knows how to retry an upload, warn about a problem, install routine OS updates and reboot cleanly once a week.

It is not a professional surveillance or backup appliance, and a power failure can still cause missing timelapse slots. But it is a practical second life for a Raspberry Pi 1—and a low-cost way to preserve the progress of a house build over years.

The lesson I learned while putting it together is simple: **the photo is only useful if you can also verify that it was saved and uploaded.**

---

**References and further reading**

- [Raspberry Pi Imager and OS](https://www.raspberrypi.com/software/)
- [Tapo C310 specifications](https://tapo.com/en/product/tapo-c310-security-camera/specs/)
- [TP-Link: Tapo RTSP/ONVIF setup](https://www.tp-link.com/pt/support/faq/2680/)
- [rclone: headless setup and SSH tunnelling](https://rclone.org/remote_setup/)
- [rclone copyto command](https://rclone.org/commands/rclone_copyto/)
- [Debian: automatic periodic updates](https://wiki.debian.org/PeriodicUpdates)
- [systemd-journald settings](https://www.freedesktop.org/software/systemd/man/latest/journald.conf.html)

*Setup described: Tapo C310 · Raspberry Pi OS Lite 32-bit · Raspberry Pi 1 · OneDrive · authenticated SMTP · package v1.4 · October 2026.*
