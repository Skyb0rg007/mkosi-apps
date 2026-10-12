
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

## Running as a system service

Each app has an example `mkosi.profiles/<app>/<app>.nspawn` for running it as
root under `systemd-nspawn@<app>.service`. The machine is a mount stack
([systemd.mstack(7)](https://www.freedesktop.org/software/systemd/man/latest/systemd.mstack.html)),
which nspawn finds by machine name like any other image:

    /var/lib/machines/soju.mstack/
    ├── layer@0.v/layer@0_0.10.1-1/   build outputs, read-only, newest is used
    ├── layer@0.v/layer@0_0.10.2-1/
    ├── layer@1/                      empty, see below
    └── bind@var/                     the container's /var: all state

Everything in it is owned by the foreign UID range, like the build outputs:

    F=2147352576
    install -d /var/lib/machines/soju.mstack/layer@0.v
    install -d -o $F -g $F /var/lib/machines/soju.mstack/layer@1 \
        /var/lib/machines/soju.mstack/bind@var
    cp -a mkosi.output/soju_0.10.1-1 \
        /var/lib/machines/soju.mstack/layer@0.v/layer@0_0.10.1-1
    cp mkosi.profiles/soju/soju.nspawn /etc/systemd/nspawn/  # then set MachineID=
    systemctl enable --now systemd-nspawn@soju.service

    # Upgrade
    cp -a mkosi.output/soju_0.10.2-1 \
        /var/lib/machines/soju.mstack/layer@0.v/layer@0_0.10.2-1
    systemctl restart systemd-nspawn@soju.service

Rolling back is removing the newest version and restarting. The apps migrate
their own data on start, so a rollback past a schema change needs a backup of
`bind@var`.

- The versions must be real directories: `layer@0.v/` ignores symlinks.
- `layer@1/` keeps the image read-only. A single layer would be bind mounted
  as the root, which systemd 261 leaves writable even though it lists it as
  read-only, so the container could change the image. Two layers become an
  overlayfs without a writable layer, which is read-only.
- `PrivateUsers=managed`, which `.mstack/` requires, takes the container's
  UID range from `systemd-nsresourced`. `systemd-mountfsd` maps the
  foreign-owned directories onto it, so `bind@var` stays foreign-owned no
  matter which range a boot gets.
- Copy outputs that `mkosi boot` has not run: it boots the output directory
  itself and leaves state behind in it, such as `/etc/machine-id`.
- Users must keep their IDs across image versions. `StateDirectory=` re-owns
  its directory when they change, but nothing re-owns PostgreSQL's data.
- With the root read-only, the machine ID comes from `MachineID=`. Without
  it, every boot gets a new one, and with it a new journal directory.
- A settings file in `/etc/systemd/nspawn/` is used instead of the one mkosi
  writes next to the output from `mkosi.nspawn`, so its root autologin does not
  apply. `machinectl shell <app>` gives a root shell.
- `Port=` forwards connections to the host's addresses, but not to
  `127.0.0.0/8`. The host side of the veth needs configuring, e.g. by
  systemd-networkd's `80-container-ve.network`.

### miniflux credentials

`.nspawn` files cannot pass credentials, and nspawn forwards only those named
with `--load-credential=`, so miniflux's go in a drop-in that repeats the
unit's `ExecStart=` (here systemd 261's):

    # /etc/systemd/system/systemd-nspawn@miniflux.service.d/credentials.conf
    [Service]
    ImportCredential=miniflux.*
    ExecStart=
    ExecStart=systemd-nspawn --quiet --keep-unit --boot --link-journal=try-guest \
            --network-veth -U --settings=override --machine=%i \
            --load-credential=miniflux.admin-username:miniflux.admin-username \
            --load-credential=miniflux.admin-password:miniflux.admin-password

`ImportCredential=` reads them from `/etc/credstore/`, or encrypted from
`/etc/credstore.encrypted/`:

    systemd-creds encrypt --name=miniflux.admin-password - \
        /etc/credstore.encrypted/miniflux.admin-password

A relative `--load-credential=` path names one of the unit's own credentials.
List only credentials that exist: a missing one stops the container from
starting.

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
