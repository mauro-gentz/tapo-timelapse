# Änderungen Version 1.3 gegenüber 1.2

- `CAPTURE_INTERVAL_MINUTES='30'` über `/etc/tapo-timelapse.conf`; Änderungen werden beim nächsten 5-Minuten-Timerlauf automatisch erkannt. Unterstützt werden 5, 10, 15, 20, 30 und 60 Minuten.
- Alarmprüfung zählt die tatsächlich erwarteten UTC-Zeitfenster (48 pro vollständig 30-minütigem Tag) und nennt fehlende Zeitpunkte.
- Frühere 24-Foto-Tage aus v1.2 bleiben in der Planhistorie als 60-Minuten-Tage erhalten. Die Monitoring-Startdatei wird nicht überschrieben.
- `rclone copyto` arbeitet Datei für Datei, nicht parallel; `--transfers 1 --checkers 1 --multi-thread-streams 0`.
- `RCLONE_CHUNK_SIZE='5Mi'` als RAM-schonender Standard für OneDrive.
- Gemeinsame Sperre verhindert gleichzeitige FFmpeg-Bildaufnahme und rclone-Upload. Vor anstehenden Aufnahmen pausiert der Upload zwischen Einzeldateien.
- Verbindungsfehler führen weder zur Löschung lokaler Originale noch zur Cloud-Synchronisierung mit Löschfunktion.
- Bestehende `/etc/tapo-timelapse.conf`, `/var/lib/tapo-timelapse` und rclone-Konfiguration bleiben bei einem Upgrade erhalten.

**Hinweis:** Bei extrem langsamem Internet kann eine bereits laufende Einzeldatei das nächste Foto um maximal einige Minuten verzögern. Einzelübertragungen werden nach 180 Sekunden beendet und beim nächsten Uploadlauf erneut probiert. Ein externer Ping-/Heartbeat-Monitor wird dadurch nicht ersetzt.
