# netbox

[NetBox](https://netbox.dev/), from upstream's release tarball, pinned by
checksum in `mkosi.sync`, with a local PostgreSQL
([mkosi.include/postgresql](../../mkosi.include/postgresql/README.md)) and
Redis ([mkosi.include/redis](../../mkosi.include/redis/README.md)). nginx serves
it on port 80, with its static files and documentation, in front of gunicorn
and NetBox's background worker.

Django refuses host names with an underscore, so NetBox answers
`netbox._dhcp` with "400 Bad Request". Use the machine's name instead,
`http://netbox/`, which `nss-mymachines` resolves on the host, or its address.

The first user is created with:

    machinectl [--user] shell netbox /usr/bin/netbox-manage createsuperuser

## Configuration

`/etc/netbox/configuration.py` sets up the local services, the secrets and
the data directories. Settings of your own go in
`/etc/netbox/local_configuration.py`, which a confext adds (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration))
and which overrides anything before it, e.g. for a proxy in front:

    ALLOWED_HOSTS = ["netbox.example.com"]
    CSRF_TRUSTED_ORIGINS = ["https://netbox.example.com"]

Then `systemctl restart netbox netbox-rq`. Plugins need installing into the
image's virtualenv, which this image does not do.

## Notes

- `netbox-setup.service` generates `SECRET_KEY` and an API token pepper once,
  into `/var/lib/netbox/secrets/`, and after a new release runs what upstream's
  `upgrade.sh` does to the database. Uploads and custom scripts are in
  `/var/lib/netbox/`.
- `netbox-manage` runs NetBox's `manage.py` as the `netbox` user, with the
  image's configuration.
- NetBox pins only its direct dependencies. `requirements.lock` pins all of
  them, resolved with `update-requirements` as of the release date, wheels only
  and hashed (see [Source builds](../../docs/design.md#source-builds)). It uses
  psycopg's binary wheel instead of its C build, which is only published as
  source. On an upgrade, run `update-requirements` after `mkosi.sync` has
  unpacked the new release.
