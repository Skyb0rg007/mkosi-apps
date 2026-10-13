# wakapi

[Wakapi](https://wakapi.dev/), a WakaTime-compatible coding statistics
server, from upstream's release binary, pinned by checksum in `mkosi.sync`.
Its web UI and API are on port 80, its SQLite database in `/var/lib/wakapi/`.

The first account is created by signing up in the web UI. WakaTime plugins
then point at the instance with, in `~/.wakatime.cfg`:

    [settings]
    api_url = http://wakapi._dhcp/api
    api_key = <the API key from Wakapi's settings>

## Configuration

Wakapi reads environment variables, from `/etc/wakapi.conf` if it exists
(see [Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
e.g.:

    WAKAPI_PUBLIC_URL=https://wakapi.example.com
    WAKAPI_INSECURE_COOKIES=false
    WAKAPI_ALLOW_SIGNUP=false

`WAKAPI_INSECURE_COOKIES` is `true` by default, since the container serves
plain HTTP; behind an HTTPS proxy, set it to `false`. Upstream's
[config.default.yml](https://github.com/muety/wakapi/blob/master/config.default.yml)
and its `config/config.go` list the variables.

## Notes

- `wakapi-secret.service` generates the password salt and the cookie key once,
  into `/var/lib/wakapi-secret/`, so that they survive upgrades: every password
  hash depends on the salt. To move an existing instance in, set its
  `WAKAPI_PASSWORD_SALT` in `/etc/wakapi.conf`, which overrides the generated
  one.
- "Failed to find configuration config.yml" in the log is expected: there is
  no config file, only the environment.
