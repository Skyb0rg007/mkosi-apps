
# mkosi-apps

This repo contains minimal mkosi-based images for different applications.

## Building an app

Each app is a profile in `mkosi.profiles/<app>/`, built one at a time as the
main image on top of `mkosi.images/minimal-base`:

    mkosi --profile=soju build          # mkosi.output/soju_0.10.1-1/
    mkosi --profile=soju boot           # rootless nspawn, machine "soju"
    mkosi --profile=soju,vm build       # mkosi.output/vm/soju_0.10.1-1.raw

The `vm` profile turns any app into a bootable disk for `systemd-vmspawn`. Its
outputs go to `mkosi.output/vm/`, because for a disk image mkosi also creates a
symlink with the name a directory build would use. Without an app profile,
`mkosi build` produces the bare base image as `mkosi.output/image`.

`mkosi boot` names the machine after the app (`Machine=`), so its `.nspawn`
settings are found and it is reachable from the host as `<app>._dhcp`. Started
by hand, `systemd-nspawn` names the machine after the versioned directory
instead and finds no settings file.

### Versions

An app's version lives in `mkosi.profiles/<app>/mkosi.version` as
`<upstream>-<revision>`, e.g. `0.10.1-1`. It names the output, lands in
`IMAGE_VERSION=` in os-release, and sorts correctly for `systemd-vpick` and
`systemd-sysupdate`, including upstream `0.10.1.1` against `0.10.1-2`.

- New upstream release: set the new upstream version with revision `1`, and
  update the checksum in the app's `mkosi.sync`. The sync scripts derive the
  upstream version from `mkosi.version`, so it is written down only once.
- Image-only change: bump the revision.

### miniflux

The miniflux image is configured entirely through system credentials, all
optional:

| Credential | Effect |
|---|---|
| `miniflux.admin-username`, `miniflux.admin-password` | Create this admin user if it does not exist yet |
| `miniflux.database-url` | Use this PostgreSQL; without it a local one runs |
| `miniflux.conf` | Further settings in Miniflux's config file format, e.g. `BASE_URL=…` |

Without `miniflux.database-url`, `miniflux-postgresql-setup.service` creates a
Debian cluster (`pg_createcluster`) on first boot, plus a `miniflux` role and
database; later boots start it through Debian's `postgresql.service` like any
other cluster. Miniflux connects over the Unix socket with Debian's default
peer authentication, so there is no database password. The cluster cannot ship
in the image, since Debian's install-time `pg_createcluster` fails in mkosi's
single-UID build (the `initdb failed` message during the build is harmless).
`/etc/postgresql` links to `/var/lib/postgresql/etc`, so the clusters'
configuration lives in `/var` with their data, and `/etc` can be read-only.

A major PostgreSQL upgrade needs one image with both server versions installed,
so that `pg_upgradecluster` can migrate the old cluster.

Miniflux runs its migrations on every start and listens on `0.0.0.0:8080`
unless `miniflux.conf` says otherwise:

    mkosi --profile=miniflux \
        --credential=miniflux.admin-username=admin \
        --credential=miniflux.admin-password=… \
        boot

## Host setup

mkosi bootstraps its Debian tools tree with the host's apt, which reads the
archive keyring from exactly `/usr/share/keyrings/debian-archive-keyring.gpg`.
On NixOS:

    systemd.tmpfiles.rules = [
      "L+ /usr/share/keyrings/debian-archive-keyring.gpg - - - - ${pkgs.debian-archive-keyring}/share/keyrings/debian-archive-keyring.gpg"
    ];

mkosi runs directly from the dev shell, not wrapped in `buildFHSEnv`: inside
bubblewrap's user namespace `systemd-nsresourced` refuses the range mkosi asks
for at startup (`DynamicRangeUnavailable`).

`mkosi.tools.conf/mkosi.prepare` gives the tools tree an `/etc/static` symlink
so that NixOS's `/etc/resolv.conf` resolves inside mkosi's sandboxes; without
it, go in a sync script cannot look up hosts. The script explains the details.

## Source builds

App sources are fetched online and built offline, the split
[tine](https://github.com/amutable-systems/tine) uses. An image's `mkosi.sync`
downloads and verifies the release, then resolves its dependencies into a
cache under `mkosi.cache/` against the project's own lockfile. Its build
script runs without network and reads only that cache. For Go (`soju`) the
cache is go's module proxy layout, served to the build as `GOPROXY=file://…`
with `-mod=readonly`. The tools tree's `golang-go` fetches (sync scripts run
there); the image's own `golang-go` from `BuildPackages=` compiles.

## Rootless containers

An app is built as a directory (`Format=directory`) owned by the systemd
foreign UID range, which is what unprivileged `systemd-nspawn --directory=`
requires. Build and boot need no privileges.

`mkosi boot` gives the container a veth link (`RuntimeNetwork=interface`). The
host side is named `ns-<hex>`, which systemd's shipped `80-namespace-ns.network`
configures with a DHCP server and masquerading; on NixOS the firewall also has
to accept DHCP on it, e.g. `networking.firewall.trustedInterfaces = [ "ns-+" ]`.

`ForeignUIDRange=yes` makes mkosi shift the finished tree itself with
`systemd-dissect --shift`, inside a user namespace `systemd-nsresourced` maps
the foreign range into. No polkit check is involved, and the next
`mkosi -f build` removes the foreign-owned tree on its own. The shift needs
systemd 258 or newer in the tools tree, which is why that tree tracks Debian
testing while the images stay on trixie.

### Why not a disk image

`systemd-nspawn --image=` on a `Format=disk` output has to go through
`systemd-mountfsd`, which fails unprivileged with
`io.systemd.InteractiveAuthenticationRequired` — an admin prompt. Only the
foreign-owned directory avoids that.

### Every file is owned by image root

mkosi builds in single-UID mode here, so every inode is owned by the invoking
user before the shift and by foreign UID 0 after it. Files that a package would
install owned by a service user land as root instead; use `StateDirectory=` or
tmpfiles `z`/`Z` where that matters.
