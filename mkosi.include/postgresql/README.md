# postgresql

A local PostgreSQL for the apps that include this directory from their
profile (`Include=%D/mkosi.include/postgresql`).

`postgresql-setup@<name>.service` creates a Debian cluster (`pg_createcluster`)
on the first boot, plus a role and a database named `<name>`, and starts
existing clusters if nothing else has. Apps order their services after it, and
connect as their system user `<name>` over the Unix socket in
`/run/postgresql`, with Debian's default peer authentication, so there is no
database password.

- The cluster cannot ship in the image: Debian's install-time
  `pg_createcluster` fails in mkosi's single-UID build (the `initdb failed`
  message during the build is harmless).
- `/etc/postgresql` links to `/var/lib/postgresql/etc`, so the clusters'
  configuration lives in `/var` with their data.
- On the first boot of a machine, `postgresql-generator` runs before tmpfiles
  links `/etc/postgresql`, so it finds no cluster to start; the setup service
  starts them instead.
- A major PostgreSQL upgrade needs one image with both server versions
  installed, so that `pg_upgradecluster` can migrate the old cluster.
