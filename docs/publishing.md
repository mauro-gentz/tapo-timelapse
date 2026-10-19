# Publishing this repository on GitHub

## 1. Before publishing

- Search the repository for passwords, OAuth tokens, private IP addresses that you don't want public, personal email addresses, or client data. Only the dummy example configuration should be committed.
- Never copy `/etc/tapo-timelapse.conf`, `/home/*/.config/rclone/rclone.conf`, or `/var/lib/tapo-timelapse/` into this repository.
- Decide whether you want **Public** (anyone can see it) or **Private** (only approved collaborators).
- Select a license **explicitly**. No license is included by default. MIT is a common option if you want others to reuse the code; consult your own requirements before selecting.
- The scripts are AI-assisted, have had offline tests, and must be tested on each target Pi/camera combination.

## 2. Create an empty GitHub repo

Go to https://github.com/new and use:

- Name: `tapo-c310-timelapse`
- Description: `Headless Tapo C310 timelapse on Raspberry Pi with OneDrive backups and SMTP monitoring`
- Visibility: public or private, your choice
- Do **not** generate a second README or `.gitignore` (already present here).

## 3. Publish from your computer

From a terminal inside the extracted repository folder:

```bash
git init -b main
git add .
git status
git commit -m "Initial release: Tapo C310 Timelapse v1.4"
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/tapo-c310-timelapse.git
git push -u origin main
```

If Git prompts for `user.name` and `user.email`, configure those locally first. GitHub HTTPS authentication uses a browser/credential manager or a token, **not your GitHub account password**.

## 4. Mark the version

```bash
git tag -a v1.4.0 -m "Tapo C310 Timelapse v1.4"
git push origin v1.4.0
```

Create an optional GitHub **Release** from tag `v1.4.0`. This keeps a stable copy of the version actually installed on your Raspberry Pi, even when you later change `main`.

## 5. For future changes

Use small commits and tags (`v1.4.1`, `v1.5.0`, etc.), test on a spare SD card or system before upgrading the unattended Pi, and **do not configure automatic `git pull` installs** on the production Pi. Changes to scripts and service files should be reviewed and deliberately deployed with `sudo bash install.sh`.
