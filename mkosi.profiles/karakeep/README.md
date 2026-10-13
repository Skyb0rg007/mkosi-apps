# karakeep

[Karakeep](https://karakeep.app/), a bookmark manager, with
[Meilisearch](https://www.meilisearch.com/) for its search and Debian's
headless Chromium for its crawler's screenshots and pages that need
JavaScript. Its web UI and API are on port 80, its SQLite database and assets
in `/var/lib/karakeep/`.

The first account to sign up becomes the admin.

## Build

Upstream publishes Karakeep only as a container image. Its app is
self-contained and links nothing but glibc, so `mkosi.sync` takes the layers
of `ghcr.io/karakeep-app/karakeep` that hold it (the web app, its migrations,
the workers and monolith), pinned by digest, which is their checksum. Node.js
and Meilisearch are upstream's release binaries in the versions upstream pins,
by checksum: Karakeep needs Node.js 24, which Debian does not have.

## Configuration

Karakeep reads environment variables, from `/etc/karakeep.conf` if it exists
(see [Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
which override the image's in `/usr/lib/karakeep/karakeep.env`, e.g.:

    NEXTAUTH_URL=https://karakeep.example.com
    DISABLE_SIGNUPS=true
    OPENAI_API_KEY=…

Then `systemctl restart karakeep-web karakeep-workers`. `NEXTAUTH_URL` is the
URL its links and logins use, `http://karakeep._dhcp` by default. Upstream's
[configuration documentation](https://docs.karakeep.app/configuration/environment-variables)
lists the rest, AI tagging included.

## Notes

- `karakeep-secret.service` generates NextAuth's secret and Meilisearch's
  master key once, into `/var/lib/karakeep-secret/`, so that they survive
  upgrades.
- Video downloads (`CRAWLER_VIDEO_DOWNLOAD`) need yt-dlp, which the image
  leaves out: Debian's is too old for most sites. Full-page archives
  (`CRAWLER_FULL_PAGE_ARCHIVE`) use monolith, from upstream's image.
- Chromium runs without its sandbox, as in upstream's
  `chromedp/headless-shell`: its sandbox needs user namespaces of its own,
  inside the container's. Its DevTools port is on localhost only.
- A new Meilisearch version may need its index migrated, so it only changes
  when upstream's pin does.
