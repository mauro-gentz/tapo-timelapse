# Release v1.4 — Per-photo Uploads and Unattended Maintenance

- `UPLOAD_AFTER_CAPTURE='yes'`: upload each image as soon as it is saved, sequentially using rclone.
- Catch-up upload scheduled hourly at XX:10 UTC for missing or modified files.
- Local `.uploaded/` receipts avoid redundant uploads; local retention still requires successful `rclone check` before deletion.
- Daily audits and SMTP alerts continue to use historical capture intervals.
- New hourly health checks monitor missing images, available disk space, failed audit/APT/reboot services, and pending update-related reboots.
- Stable Debian, Raspbian and Raspberry Pi package updates are installed automatically from the current release repositories; no automated OS-major upgrades or APT-triggered reboots.
- Graceful weekly reboot: Sunday at 04:10 UTC, delayed or skipped when capture, upload or package maintenance is running. A boot confirmation email is queued when the Pi returns.
- Repairs v1.3 schedule-file ownership problems, backs up private configuration and preserves existing credentials.
