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

Without `miniflux.database-url`, Miniflux uses a local PostgreSQL (see
[mkosi.include/postgresql](../../mkosi.include/postgresql/README.md)), with a
`miniflux` role and database, over the Unix socket and without a password.
