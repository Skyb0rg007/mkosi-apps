# miniflux

[Miniflux](https://miniflux.app/), a feed reader, from Debian, with a local
PostgreSQL. Its web UI is on port 80. Miniflux runs its migrations on every
start.

## Configuration

Through system credentials (see
[Credentials](../../README.md#credentials)), all optional:

| Credential | Effect |
|---|---|
| `miniflux.admin-username`, `miniflux.admin-password` | Create this admin user if it does not exist yet |
| `miniflux.database-url` | Use this PostgreSQL; without it a local one runs |
| `miniflux.conf` | Further settings in Miniflux's config file format, e.g. `BASE_URL=…` |

For a try with `mkosi boot`:

    mkosi --profile=miniflux \
        --credential=miniflux.admin-username=admin \
        --credential=miniflux.admin-password=… \
        boot

## PostgreSQL

Without `miniflux.database-url`, `miniflux-postgresql-setup.service` creates a
Debian cluster (`pg_createcluster`) on the first boot, plus a `miniflux` role
and database, and starts existing clusters if nothing else has. Miniflux
connects over the Unix socket with Debian's default peer authentication, so
there is no database password.

- The cluster cannot ship in the image: Debian's install-time
  `pg_createcluster` fails in mkosi's single-UID build (the `initdb failed`
  message during the build is harmless).
- `/etc/postgresql` links to `/var/lib/postgresql/etc`, so the clusters'
  configuration lives in `/var` with their data.
- A major PostgreSQL upgrade needs one image with both server versions
  installed, so that `pg_upgradecluster` can migrate the old cluster.
