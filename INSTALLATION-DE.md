# Tapo C310 Timelapse v1.4 – Upgrade für Raspberry Pi 1/2

## Was ist neu?

- Aufnahme weiterhin nach `CAPTURE_INTERVAL_MINUTES` (bestehender Wert wird beibehalten, z. B. `20` = 72 Bilder/UTC-Tag).
- Jedes fertige Bild wird **zuerst lokal gespeichert**, danach **einzeln** per `rclone copyto` nach OneDrive hochgeladen.
- **FFmpeg und rclone teilen sich ein exklusives Dateischloss** – sie laufen nicht gleichzeitig. Läuft ein Cloudtransfer bereits, kann er den nächsten Aufnahmetermin um höchstens einige Minuten verzögern.
- Beim Übertragen wird pro Datei eine lokale Erfolgsmarkierung (`.uploaded/.../*.ok`) hinterlegt. Sie vermeidet wiederholte Uploadversuche bereits übertragener Dateien. Bei Dateigrößenänderung wird erneut übertragen.
- Ein **stündlicher Nachhol-Timer** prüft noch nicht hochgeladene Bilder, auch vom heutigen Tag.
- Die **tägliche Vollständigkeitsprüfung** gegen alle geplanten Zeitslots und OneDrive bleibt aktiv.
- Ein **stündlicher Gesundheitscheck** prüft fehlende frische Aufnahmen (>90 min), Speicherplatz (<20% frei), technische Audit-Fehler, fehlgeschlagene APT-Updates und fehlgeschlagene Wochenneustarts. SMTP nutzt die bestehende lokale Mailwarteschlange.
- Installiert `unattended-upgrades` für tägliche Updates aus dem vorhandenen Debian/Raspbian/Raspberry-Pi-Release, **ohne automatische Major-OS-Upgrades** und ohne von APT ausgelöste automatische Neustarts.
- Ist `/run/reboot-required` vorhanden, verschickt das System einmal je Boot eine E-Mail "Neustart notwendig".
- **Sonntag 04:10 UTC** (Portugal Winter 04:10, Sommer 05:10) führt Linux automatisch einen **geordneten Neustart** durch. Der Dienst wartet auf laufende Kamera-/Uploadvorgänge und bricht bei gleichzeitigem APT-Update ab.
- Beim Hochfahren folgt eine **Neustartbestätigung per E-Mail**. Bleibt der Pi ganz ohne Strom oder Internet, kann er währenddessen **keine E-Mail versenden**.

## Sicherheits- und Stromhinweis

> **Nicht** wöchentlich den Netzstecker ziehen! Der neue Timer führt automatisch einen *sauberen* `systemctl reboot` aus. Dabei beendet Linux Prozesse und synchronisiert das Dateisystem. Ein hartes Ausschalten/Anschalten kann die SD-Karte beschädigen oder das Dateisystem korrupt machen. Ein gelegentlicher harter Neustart ist eine Notlösung, nicht der reguläre Betriebsmodus. Ein externer Heartbeat-Dienst ist nötig, um über einen vollständigen Stromausfall sofort benachrichtigt zu werden.

## Upgrade aus v1.3/v1.3.1

1. ZIP nach `/home/master/` auf den Raspberry Pi übertragen.
2. Per SSH als `master` anmelden; **nicht** `su -` nach `root` verwenden.
3. Entpacken und installieren:

```bash
cd /home/master
unzip tapo-pi2-timelapse-c310-v1.4.zip
cd tapo-pi2-timelapse-c310-v1.4
sudo bash install.sh
```

Die Installation kann wegen `apt-get update` und neuer Pakete einige Minuten dauern. Sie ersetzt keine bestehenden Aufnahmen oder Cloud-Konfigurationen. Falls die alte `.capture-schedule.json` ungewollt `root` gehörte, wird sie wieder auf den Dienstbenutzer gesetzt. Eine Sicherung der vorhandenen privaten Konfiguration wird unter `/var/backups/tapo-timelapse/tapo-timelapse.conf.pre-v1.4` gespeichert (nur für root lesbar).

## Konfiguration

```bash
sudo nano /etc/tapo-timelapse.conf
```

Die Installation ergänzt fehlende neue Schlüssel automatisch:

```ini
CAPTURE_INTERVAL_MINUTES='20'
UPLOAD_AFTER_CAPTURE='yes'
EMAIL_ON_BOOT='yes'
HEALTH_FREE_SPACE_PERCENT='20'
HEALTH_STALE_MINUTES='90'
UPLOAD_FILE_TIMEOUT_SEC='180'
```

Falls deine vorhandene Datei bereits `CAPTURE_INTERVAL_MINUTES='20'` enthält, bleibt es bei 72 Fotos pro vollständigem UTC-Tag. Wird ein Foto erfolgreich aufgenommen, läuft direkt danach rclone. Die Cloudverbindung kann unabhängig davon vorübergehend ausfallen – die lokale Aufnahme zählt trotzdem als erfolgreich.

`UPLOAD_AFTER_CAPTURE='no'` deaktiviert den unmittelbaren Einzel-Upload; der stündliche Nachhol-Timer bleibt weiterhin eingeschaltet. `EMAIL_ON_BOOT='no'` deaktiviert die Boot-Bestätigung, nicht die Fehleralarme. Die *Wochenneustartzeit* wird vom systemd-Timer festgelegt (nicht von der Config).

## Prüfen

```bash
tapo-timelapse status
systemctl list-timers --all 'tapo-*.timer' 'apt-daily*'
tapo-timelapse mail-test
sudo systemctl start tapo-health.service
sudo journalctl -u tapo-health.service -n 30 --no-pager
sudo unattended-upgrade --dry-run --debug
```

Optional eine neue Testaufnahme (**kein Eintrag in der regulären Tagesfolge**):

```bash
tapo-timelapse test
```

Die nächste Aufnahme zum regulären Slot (z. B. XX:00, XX:20 oder XX:40 UTC) erzeugt automatisch die vollständige Kette. Danach:

```bash
sudo journalctl -u tapo-capture.service -n 45 --no-pager
sudo journalctl -u tapo-upload.service -n 45 --no-pager
```

Erwartete Meldungen sind `Gespeichert:` und `OneDrive erfolgreich:`. Fehlgeschlagene Uploads bleiben lokal und können mit dem folgenden Befehl sofort nachgeholt werden:

```bash
sudo systemctl start tapo-upload.service
sudo journalctl -u tapo-upload.service -n 50 --no-pager
```

Bitte **nicht** manuell `sudo tapo-timelapse status` ausführen: Benutze normale Nutzerrechte, um eine erneute Erstellung von root-eigenen Statusdateien aus älteren Versionen zu vermeiden. Der Hotfix ist enthalten, diese Vorsicht bleibt dennoch sinnvoll.

## Update-/Neustartverhalten

- `unattended-upgrades` startet über die regulären APT-Timer. Paketlisten werden täglich aktualisiert. Erlaubt sind die signierten Pakete der laufenden Debian-/Raspbian-Release-Version und des Raspberry-Pi-Repositorys, **keine neuen Debian-Releases**.
- APT-Neustarts sind deaktiviert; sie werden über `/run/reboot-required` erkannt, soweit die beteiligten Pakete diese Datei erzeugen. Bei manchen Raspberry-Pi-Firmwareupdates gibt es möglicherweise keine solche Markierung; der wöchentliche Neustart trägt diese trotzdem ein.
- Auto-Updates und Kamera können sich zeitlich überlappen. Die Paketinstallation erhält niedrige CPU- und I/O-Priorität. Ein schweres Update kann die Aufnahme dennoch verzögern. Bei problematischen Updates wird eine Warnung versendet, sofern der Pi läuft und SMTP funktioniert.
- Sonntags um **04:10 UTC** startet der Pi selbstständig sauber neu. Nicht während eines laufenden APT-Upgrades. Maximal 10 Minuten Wartezeit für laufende Kamera-/Cloudaktivität, danach wird der Neustart ausgelassen und dies bei der nächsten Gesundheitsprüfung gemeldet.
- Ausbleibende Bilder werden weiterhin beim nächsten vollständigen Tagesaudit über die hinterlegte Intervallhistorie erkannt. Einen völlig ausgeschalteten Pi kann das System nicht selbst aus der Ferne melden.

### Updateprotokoll

```bash
sudo tail -n 60 /var/log/unattended-upgrades/unattended-upgrades.log
sudo journalctl -u apt-daily-upgrade.service -n 60 --no-pager
sudo journalctl -u tapo-weekly-reboot.service -n 30 --no-pager
```

### Nach einem Neustart

```bash
systemctl is-enabled tapo-capture.timer tapo-upload.timer tapo-audit.timer tapo-mail.timer tapo-health.timer tapo-weekly-reboot.timer
systemctl is-active tapo-capture.timer tapo-upload.timer tapo-audit.timer tapo-mail.timer tapo-health.timer tapo-weekly-reboot.timer
sudo journalctl -b -1 -n 30 --no-pager
```

## Dateiorganisation

- Originale: `/var/lib/tapo-timelapse/YYYY/MM/DD/YYYY-MM-DD_HH-MM-00Z.png`
- Upload-Receipts: `/var/lib/tapo-timelapse/.uploaded/YYYY/MM/DD/...png.ok`
- OneDrive: `onedrive:Timelapse/Grundstueck/YYYY/MM/DD/`
- Private Config: `/etc/tapo-timelapse.conf`
- SMTP-Warteschlange: `/var/lib/tapo-timelapse/.mailqueue/`

Die alten lokalen Bilddateien werden weiterhin erst nach 14 Tagen und nur nach einem erfolgreichen rclone-Gegencheck gelöscht. In OneDrive bleibt alles gespeichert.

## Was ist nicht möglich?

- Bei **komplettem Stromausfall**, LAN- oder Internetdefekt kann der Pi keine eigene E-Mail versenden. Dazu müsste ein externer Dienst seine Erreichbarkeit überwachen.
- Weder `unattended-upgrades` noch dieser Installer aktualisieren das Python-/Shell-Timelapse-Projekt selbst automatisch; spätere Versionen müssen bewusst eingespielt werden.
- Größere OS-Versionssprünge werden bewusst nicht automatisiert. Sie benötigen zuvor ein SD-Karten-Backup und Funktionsprüfung.
- Ein E-Mail-Log zeigt, ob der SMTP-Server Nachrichten akzeptierte, nicht ob der Empfänger sie tatsächlich gelesen hat.
