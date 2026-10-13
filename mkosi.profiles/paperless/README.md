# paperless

[Paperless-ngx](https://docs.paperless-ngx.com/), a document management system,
from upstream's release tarball, pinned by checksum in `mkosi.sync`, with a
local Redis ([mkosi.include/redis](../../mkosi.include/redis/README.md)) and
SQLite. Its web UI is on port 80, served by granian, with Celery's worker and
scheduler and the consumption directory's watcher beside it. OCR covers
English, German, French, Italian and Spanish, as in upstream's container
image.

Django refuses host names with an underscore, so paperless answers
`paperless._dhcp` with "400 Bad Request". Use the machine's name instead,
`http://paperless/`, which `nss-mymachines` resolves on the host, or its
address.

The web UI asks for the first user on its first visit, or:

    machinectl [--user] shell paperless /usr/bin/paperless-manage createsuperuser

Documents come in through the web UI, the API, mail, or the consumption
directory `/var/lib/paperless/consume/`. Everything paperless keeps is in
`/var/lib/paperless/`: the database and search index in `data/`, the documents
in `media/`.

## Configuration

Paperless reads `/etc/paperless.conf` if it exists, which a confext adds (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
in the format of upstream's
[paperless.conf.example](https://github.com/paperless-ngx/paperless-ngx/blob/main/paperless.conf.example),
e.g.:

    PAPERLESS_URL=https://paperless.example.com
    PAPERLESS_OCR_LANGUAGE=deu+eng
    PAPERLESS_TIME_ZONE=Europe/Berlin

Then restart the `paperless-*` services. The paths are set in
`/usr/lib/paperless-ngx/paperless.env`, which takes precedence over the file.
For PostgreSQL instead of SQLite, set `PAPERLESS_DBENGINE=postgresql` and its
`PAPERLESS_DB*` settings; MariaDB's driver is not included.

## Notes

- `paperless-setup.service` generates the secret key once, into
  `/var/lib/paperless/secret.env`, and migrates the database on every start,
  as upstream's container image does. Paperless-ngx 3 only upgrades from
  2.20.15 or later.
- `paperless-manage` runs paperless's `manage.py` as the `paperless` user, with
  the image's settings, e.g. for `document_exporter`.
- The image is large, about 3 GB: paperless-ngx 3 depends on PyTorch, if only
  its CPU build, for its AI features.
- `requirements.lock` is upstream's `requirements.txt`, which covers every
  platform, resolved for the image's Python with `update-requirements`. It
  leaves out the drivers that are only published as source for Python 3.13,
  mysqlclient and psycopg-c; psycopg uses `libpq` directly instead. On an
  upgrade, run `update-requirements` after `mkosi.sync` has unpacked the new
  release.
- The build replaces Debian's ImageMagick policy with upstream's, which allows
  reading PDFs for thumbnails.
