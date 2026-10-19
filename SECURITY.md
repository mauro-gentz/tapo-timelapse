# Security

This project processes camera credentials, an OAuth-enabled rclone configuration, and SMTP passwords.

- **Never** open a public issue or commit containing passwords, OAuth refresh/access tokens, or live configuration files.
- Keep `/etc/tapo-timelapse.conf` restricted to the service account and administrator.
- Keep the camera on a trusted LAN; do not publish camera RTSP ports or Pi SSH directly to the Internet.
- Review changes to the shell installer before executing it with `sudo`.
- Use a dedicated camera account and a dedicated SMTP app password where possible.
- If credentials are accidentally published, **rotate the credentials**; deleting a commit does not guarantee the data has disappeared from Git history or clones.

Security contact details can be added by the repository owner before making the repo public. Do not put secrets into GitHub Actions variables unless they are strictly needed; current CI uses no secrets.
