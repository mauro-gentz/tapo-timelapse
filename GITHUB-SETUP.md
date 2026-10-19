# Publish or Replace This GitHub Repository

This package contains the translated **v1.4** source files and documentation. Your existing Raspberry Pi is not updated by a Git push.

## Create the repository for the first time

1. Visit https://github.com/new and create an empty repository named `tapo-c310-timelapse` (public or private as you prefer).
2. Do **not** generate a README or .gitignore, because this package includes both.
3. Unzip the package locally and open PowerShell inside the extracted source directory.

```powershell
git init -b main
git add -A
git status
git commit -m "Initial release: Tapo C310 Timelapse v1.4"
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/tapo-c310-timelapse.git
git push -u origin main
```

## Replace the last incorrect push

If you accidentally uploaded an incorrect set of files as your **latest commit**, copy the contents of this corrected package into your **existing local clone**. Keep the existing hidden `.git` directory. From that directory:

```powershell
git status
git log -3 --oneline
git add -A
git commit --amend -m "Initial release: Tapo C310 Timelapse v1.4 (English)"
git push --force-with-lease origin main
```

`--force-with-lease` refuses to overwrite unexpected remote changes. Only amend the tip commit if the repository is yours and no collaborators rely on it. If you want to keep its history intact, create an ordinary new commit instead:

```powershell
git add -A
git commit -m "Replace initial files with English documentation and messages"
git push origin main
```

If `v1.4.0` was already tagged against the incorrect commit, decide whether to replace that tag or publish a new one. To **replace** the existing tag after confirming there is no GitHub Release depending on it:

```powershell
git tag -d v1.4.0
git push origin :refs/tags/v1.4.0
git tag -a v1.4.0 -m "Tapo C310 Timelapse v1.4 English release"
git push origin v1.4.0
```

Note: Removing a tag/force-pushing does not guarantee the old objects disappear from forks, clones, caches, or GitHub release assets. If you accidentally published **credentials**, immediately rotate or revoke them, and consider GitHub's sensitive-data removal procedures. Do not rely on Git history rewriting as a security measure.

## Before every push

- Run `git status` and `git diff --cached --stat`.
- Never commit real `/etc/tapo-timelapse.conf`, any `rclone.conf`, `.uploaded`, `.mailqueue`, OAuth tokens, photos or private email credentials.
- The repository contains **no license yet**. Choose one explicitly if you want to grant reuse and redistribution rights.
- Do not enable automatic `git pull` on an unattended production Raspberry Pi.
