# victoriametrics

Single-node [VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/)
with its vmui web UI on port 80, plus upstream's vmutils, from upstream's
release binaries, pinned by checksum in `mkosi.sync`. It scrapes its own
metrics every 10s from the start.

## Configuration

Files in `/etc/victoriametrics/`, all optional, which a confext adds (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)):

| File | Effect |
|---|---|
| `scrape.yml` | Prometheus `scrape_configs` for VictoriaMetrics to scrape |
| `vmagent.yml` | Run vmagent (port 8429) with these `scrape_configs`, writing into VictoriaMetrics |
| `rules/*.yml` | Run vmalert (port 8880) with these alerting and recording rules; vmui shows its alerts |
| `vmauth.yml` | Run vmauth (port 8427) with this auth config |
| `victoria-metrics.env`, `vmagent.env`, `vmalert.env`, `vmauth.env` | Flags as environment variables, `-retentionPeriod=1y` as `retentionPeriod=1y`; they replace the units' defaults, lists included |

- vmalert stores its alerts' state and its recording rules' results in
  VictoriaMetrics. It notifies nobody until `vmalert.env` sets `notifier_url`
  or `notifier_config`, together with `notifier_blackhole=false`.
- Each service rereads its config files on `systemctl reload`; a changed `.env`
  file takes a restart.
- Secrets can come as system credentials named `victoriametrics.*`, which the
  services import, for flags and config fields that take a file path, e.g.
  `/run/credentials/vmalert.service/victoriametrics.token`.

## Backups

vmbackup, vmrestore, vmctl and vmalert-tool are there to run by hand, e.g. a
backup into the machine's `/var`:

    machinectl [--user] shell victoriametrics /usr/bin/vmbackup \
        -storageDataPath=/var/lib/victoria-metrics \
        -snapshot.createURL=http://localhost/snapshot/create \
        -dst=fs:///var/backups/victoria-metrics
