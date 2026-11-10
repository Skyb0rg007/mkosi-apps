# searxng

[SearXNG](https://docs.searxng.org/), a metasearch engine, from upstream's
source at a pinned commit, with its Python dependencies from hashed wheels
(see [Source builds](../../docs/design.md#source-builds)). granian serves it
on port 80, as in upstream's container image. It keeps nothing but its
caches, in `/var/cache/searxng/`.

## Configuration

SearXNG reads `/etc/searxng/settings.yml`, which a confext replaces (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)).
The image's starts from upstream's defaults with `use_default_settings: true`
and changes a few; upstream's
[settings documentation](https://docs.searxng.org/admin/settings/index.html)
lists the rest, e.g.:

    use_default_settings: true
    general:
      instance_name: My search
    server:
      base_url: https://search.example.com/
      image_proxy: true
    search:
      formats: [html, json]
    engines:
      - name: wikidata
        disabled: true

Then `systemctl restart searxng`. Environment variables, such as granian's
`GRANIAN_WORKERS` or `SEARXNG_VALKEY_URL`, go in `/etc/searxng/searxng.conf`.

## Notes

- SearXNG has no releases, so the version is the commit's time in UTC and its
  hash, `<year>.<month>.<day>.<hhmmss>.<hash>`: upstream's own
  `<date>+<hash>`, which the web UI shows, has a `+` that systemd-vpick does
  not accept, and the time keeps two commits of a day in order.
  `bin/update-apps searxng` takes the newest commit, `searxng=COMMIT` another.
- `searxng-secret.service` generates the secret key once, into
  `/var/lib/searxng-secret/`, which signs the preferences cookie and the image
  proxy's URLs; `SEARXNG_SECRET` passes it on.
- The limiter, which blocks bots on public instances, is off: it needs Valkey,
  and a client IP that only a reverse proxy in front gives, through
  `X-Forwarded-For`. Without that header SearXNG logs an error for each
  request, which is harmless.
- The Tor engines (ahmia, torch) fail to load, as they do without
  `outgoing.using_tor_proxy`.
- SearXNG fetches engine data and the ClearURLs rules as it starts, so the
  machine's network only counts as online once DHCP has given it an address
  and DNS servers, rather than at its IPv6 link-local address.
