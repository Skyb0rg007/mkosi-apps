# victorialogs

Single-node [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) with
its web UI and ingestion APIs on port 80, plus vlagent and vlogscli, from
upstream's release binaries, pinned by checksum in `mkosi.sync`.

## Configuration

Flags come as environment variables from `/etc/victorialogs/victoria-logs.env`,
which a confext adds (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
e.g. `retentionPeriod=30d` for `-retentionPeriod=30d` (the default is 7 days).
Secrets can come as system credentials named `victorialogs.*`.

## Shipping the host's journal

    systemd-journal-upload --url=http://victorialogs._dhcp:80/insert/journald

The URL needs its port: without one, `systemd-journal-upload` appends its
default 19532 after the path.
