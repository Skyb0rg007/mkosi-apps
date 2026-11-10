# immich

[Immich](https://immich.app/), a photo and video server, with a local
PostgreSQL, with [VectorChord](https://github.com/tensorchord/VectorChord) and
pgvector, and Redis. Its web UI and API are on port 80, its uploads,
thumbnails, encoded videos and database backups in `/var/lib/immich/`.

The first account to sign up becomes the admin.

## Build

Upstream publishes the server only as a container image, on Debian trixie,
whose base image builds libvips, ImageMagick, libheif, libjxl, libraw and
jpegli itself, and the server's sharp against them. `mkosi.sync` takes the
layers of `ghcr.io/immich-app/immich-server` that hold those libraries (its
`/usr/local/lib`, where they stay, as built), the geodata for reverse
geocoding, the server, the web client, the CLI and the core plugin, pinned by
digest, which is their checksum. Debian provides what they link to. Node.js is
upstream's release binary, jellyfin-ffmpeg and VectorChord's PostgreSQL 17
extension their Debian packages, in the versions upstream's image and its
`docker-compose.yml` pin, by checksum.

## Configuration

Immich reads environment variables, from `/etc/immich.conf` if it exists (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
which override the image's in `/usr/lib/immich/immich.env`; upstream's
[environment variables](https://docs.immich.app/install/environment-variables)
lists them. Most settings, though, are in the web UI's administration pages,
stored in the database.

Smart search, face recognition and text recognition (OCR) need upstream's
machine-learning service, which is not in the image: it runs ONNX models,
best on a GPU. To use one elsewhere, e.g. upstream's
`immich-machine-learning` container:

    IMMICH_MACHINE_LEARNING_ENABLED=true
    IMMICH_MACHINE_LEARNING_URL=http://ml.example.com:3003

Then `systemctl restart immich-server`.

## Notes

- `immich-database.service` creates the PostgreSQL extensions Immich needs,
  which its role, not a superuser, cannot, and updates VectorChord and
  pgvector after an upgrade, before Immich reindexes. It grants the role
  `pg_maintain` too, for the vacuum Immich runs over the whole database.
  VectorChord only works preloaded, which the cluster that
  `postgresql-setup@immich.service` creates on the first boot has, from
  `/etc/postgresql-common/createcluster.d/immich.conf`.
- `immich-admin` runs upstream's admin CLI as the `immich` user, with
  Immich's settings, e.g. `immich-admin reset-admin-password`.
- The first start imports the geodata, which takes a few seconds; meanwhile,
  the API logs a schema drift in `geodata_places` that the import resolves
  (`immich-admin schema-check`).
- The server uses jellyfin-ffmpeg's software codecs: there is no GPU in the
  container, nor Intel's OpenCL runtime, which upstream's image adds for
  hardware transcoding.
- upstream's image preloads mimalloc from Debian testing, which trixie does
  not have, so the server says it skips it, and uses glibc's allocator.
