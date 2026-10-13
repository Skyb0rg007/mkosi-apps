# homebox

[Homebox](https://homebox.software/), an inventory manager, from upstream's
release binary, pinned by checksum in `mkosi.sync`. Its web UI and API are on
port 80, its database and uploads in `/var/lib/homebox/`.

## Configuration

Homebox reads environment variables, from `/etc/homebox.conf` if it exists
(see [Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
e.g. to stop sign-ups once your account exists:

    HBOX_OPTIONS_ALLOW_REGISTRATION=false

## Notes

- `homebox-secret.service` generates the API key pepper once, into
  `/var/lib/homebox-secret/`, so that it survives upgrades; API keys stop
  working if it changes.
- `HBOX_WEB_HOST=[::]` is set because, with no host, Homebox also opens a
  listener on port 80 that it never uses, and then fails to bind its own.
