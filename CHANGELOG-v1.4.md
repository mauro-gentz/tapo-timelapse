# Tapo C310 Timelapse v1.4

- `UPLOAD_AFTER_CAPTURE='yes'`: Bild sofort nach dem lokalen Speichern seriell per rclone hochladen.
- Nachhol-Upload jede Stunde um XX:10 UTC, ausschließlich fehlende bzw. veränderte Dateien.
- `.uploaded/`-Receipts sparen wiederholte Cloudaufrufe; die finale 14-Tage-Löschung verlangt weiterhin `rclone check`.
- Tagesaudit mit SMTP-Alarmsystem bleibt enthalten, inklusive historischer Aufnahmeintervalle.
- Neuer separater stündlicher Gesundheitscheck (neue Bilder, SD frei, Audit-/APT-/Rebootdienstfehler, notwendiger Kernelneustart).
- Automatische Debian/Raspbian/Raspberry-Pi-Paketupdates innerhalb der aktuellen Release, ohne automatische APT-Reboots.
- Sauberer Wochenneustart Sonntag 04:10 UTC mit Warten auf Aufnahmen/Uploads; E-Mail-Bestätigung nach Boot.
- Automatische Berechtigungsreparatur für den v1.3-Statusdateifehler, Konfigurationsbackup und Erhalt bestehender Credentials.
