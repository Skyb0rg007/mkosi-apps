# soju

The [soju](https://soju.im/) IRC bouncer, built from source, with the
[gamja](https://codeberg.org/emersion/gamja) web client served by nginx.

- IRC, in plain text, on port 6667 (`irc+insecure://`).
- gamja on port 80, also in plain HTTP; nginx proxies its WebSocket to soju's
  `http+unix://` socket, as in soju's `contrib/nginx.md`.

Neither does TLS: that is up to a proxy in front, which holds the certificate,
e.g. nginx with the `stream` server from `contrib/nginx.md` for IRC and an
HTTPS server for gamja. The proxy must not send the PROXY protocol, which soju
only accepts from addresses listed in `accept-proxy-ip`, so soju sees the
proxy's address as every client's.

## Configuration

Users are created with `sojuctl`:

    machinectl [--user] shell soju /usr/bin/sojuctl user create -username … -password …

soju's own settings are in `/etc/soju/config`, which a confext can replace
(see [Changing an app's configuration](../../README.md#changing-an-apps-configuration));
`systemctl reload soju` rereads it. nginx's `/etc/nginx` is linked as a whole,
so a confext changing it has to carry all of it.

## Build

- soju's release is verified against emersion's key (`emersion.gpg`) and its
  checksum, and built offline (see [Source builds](../../docs/design.md#source-builds)).
- gamja's release is its unbundled source, which runs as is once its
  `node_modules/` exist. The sync script fetches the runtime dependencies that
  its `package-lock.json` pins, checked against the lockfile's hashes, so the
  image needs neither npm nor a build. gamja's version is pinned in the sync
  script, separately from soju's.
- soju runs as group `www-data`, so that nginx can connect to its socket.
