# Version 1.3.1 - schedule file ownership hotfix

- Fixed a permission regression in v1.3 where `sudo tapo-timelapse status`
  (especially immediately after changing `CAPTURE_INTERVAL_MINUTES`) could
  replace `.capture-schedule.json` with a root-owned, 0600 file. The `master`
  capture service would then fail to read the schedule and stop taking images.
- When a root-run invocation creates/replaces the schedule history or lock,
  the files are now owned by the owner of `DATA_DIR` (normally `master`).
- Existing `rclone` and SMTP configuration, schedule history, images and
  systemd timers remain unchanged during update.

## Apply the upgrade

Log in as the service user (normally `master`) and install with:

```bash
cd /home/master/tapo-pi2-timelapse-c310-v1.3.1
sudo bash install.sh
```

If a previous root-run command already changed file ownership, repair it once:

```bash
sudo chown master:master /var/lib/tapo-timelapse/.capture-schedule.json /var/lib/tapo-timelapse/.capture-schedule.lock
sudo chmod 600 /var/lib/tapo-timelapse/.capture-schedule.json /var/lib/tapo-timelapse/.capture-schedule.lock
```

Then run `tapo-timelapse status` **without** `sudo`, and check capture logs:

```bash
sudo journalctl -u tapo-capture.service --since '1 hour ago' --no-pager
```

The capture schedule checks every five minutes. At a 20-minute interval the
capture slots are XX:00, XX:20 and XX:40 UTC. A manual `tapo-timelapse test`
checks the camera without creating an hourly-slot production image.
