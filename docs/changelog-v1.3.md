# Release v1.3 — Configurable Capture Scheduling

- Added `CAPTURE_INTERVAL_MINUTES` in `/etc/tapo-timelapse.conf`, supporting 5, 10, 15, 20, 30 and 60 minutes. Changes are detected on the next five-minute polling cycle.
- Daily audits check exact UTC capture slots rather than just counting files.
- Preserved historical capture intervals, so older 24-image days remain evaluated as 60-minute days.
- OneDrive uploads run sequentially via `rclone copyto` using `--transfers 1 --checkers 1 --multi-thread-streams 0` and a 5 MiB upload chunk size.
- A shared lock prevents FFmpeg and rclone from processing simultaneously, with scheduled captures prioritized.
- Failed uploads do not delete local originals. No destructive cloud sync is used.
- Existing local images, rclone authentication and SMTP configuration are retained by the installer.

**Limitation:** A slow individual upload may delay a scheduled capture by up to a few minutes. An external monitor is still needed to detect a fully offline Pi.
