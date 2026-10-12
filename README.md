
# mkosi-apps

This repo contains minimal mkosi-based images for different applications.

## Building an app

Each app is a profile in `mkosi.profiles/<app>/`, built one at a time as the
main image on top of `mkosi.images/minimal-base`:

    mkosi --profile=soju build          # mkosi.output/soju_0.10.1-1/
    mkosi --profile=soju boot           # rootless nspawn on a throwaway copy
    mkosi --profile=soju,vm build       # mkosi.output/vm/soju_0.10.1-1.raw

The `vm` profile turns any app into a bootable disk for `systemd-vmspawn`. Its
outputs go to `mkosi.output/vm/`, because for a disk image mkosi also creates a
symlink with the name a directory build would use. Without an app profile,
`mkosi build` produces the bare base image as `mkosi.output/image`.

`mkosi boot` is for trying a build: it boots a copy of the output
(`Ephemeral=yes`) and discards it, state included. To keep an app running, see
[Running the apps](#running-the-apps). `mkosi boot` names the machine after the
app (`Machine=`), so its `.nspawn` settings are found and it is reachable from
the host as `<app>._dhcp`; an installed machine of the same name has to be
stopped first.

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

## Running the apps

`bin/install-app` installs a build as its app's machine, a mount stack
([systemd.mstack(7)](https://www.freedesktop.org/software/systemd/man/latest/systemd.mstack.html))
that `systemd-nspawn@<app>.service` finds by machine name. Without privileges
it goes to `~/.local/state/machines/` for the user's service manager, as root
to `/var/lib/machines/` for the system's:

    bin/install-app mkosi.output/soju_0.10.1-1
    systemctl --user enable --now systemd-nspawn@soju.service  # as root: no --user

    # Upgrade
    bin/install-app mkosi.output/soju_0.10.2-1
    systemctl --user restart systemd-nspawn@soju.service

The image is read-only and versioned, and all state is in `/var`:

    ~/.local/state/machines/soju.mstack/
    ├── layer@0.v/layer@0_0.10.1-1/   builds; the newest is booted
    ├── layer@0.v/layer@0_0.10.2-1/
    ├── layer@1/                      empty, see below
    └── bind@var/                     the container's /var

A new machine also gets the profile's `<app>.nspawn` settings, with a machine
ID of its own, in `~/.config/systemd/nspawn/` or `/etc/systemd/nspawn/`.
Settings there are trusted, unlike a file next to the image.

To roll back, rename the newest version to a name `layer@0.v/` ignores, e.g.
`.layer@0_0.10.2-1.old`, and restart. The apps migrate their own data on start,
so a rollback past a schema change needs a backup of `bind@var/`. Versions are
owned by the foreign UID range; as root `rm -rf` deletes one, otherwise:

    mkosi-sandbox --ro-bind / / --tmpfs /tmp --bind-foreign "$dir" /tmp/dir \
        --become-root -- find /tmp/dir -mindepth 1 -delete && rmdir "$dir"

- `layer@1/` keeps the image read-only. A single layer would be bind mounted
  as the root, which systemd 261 leaves writable even though it lists it as
  read-only, so the container could change the image. Two layers become an
  overlayfs without a writable layer, which is read-only.
- `PrivateUsers=managed`, which `.mstack/` requires, takes the container's
  UID range from `systemd-nsresourced`. `systemd-mountfsd` maps the
  foreign-owned directories onto it, so `bind@var/` stays foreign-owned no
  matter which range a boot gets. For a client without privileges, mountfsd
  only mounts a foreign-owned directory whose parent the client owns, so the
  machine directory and `layer@0.v/` stay the user's.
- `bin/install-app` refuses an output that has been booted, which leaves state
  behind in it, such as a machine ID that would take precedence over
  `MachineID=`. `mkosi -f build` replaces it.
- Users must keep their IDs across image versions. `StateDirectory=` re-owns
  its directory when they change, but nothing re-owns PostgreSQL's data.
- With the root read-only, the machine ID comes from `MachineID=`. Without
  it, every boot gets a new one, and with it a new journal directory.
- The settings leave out the root autologin of `mkosi.nspawn`;
  `machinectl [--user] shell <app>` gives a root shell.
- `Port=` needs root. Without, nspawn logs `Failed to modify AF_INET
  firewall` and carries on, and the app is reachable as `<app>._dhcp`. As
  root, it forwards connections to the host's addresses, but not to
  `127.0.0.0/8`; the host side of the veth needs configuring, e.g. by
  systemd-networkd's `80-container-ve.network`.

### miniflux credentials

`.nspawn` files cannot pass credentials, and nspawn forwards only those named
with `--load-credential=`, so miniflux's go in a drop-in that repeats the
unit's `ExecStart=` (see `systemctl [--user] cat systemd-nspawn@.service`):

    # ~/.config/systemd/user/systemd-nspawn@miniflux.service.d/credentials.conf
    [Service]
    ImportCredential=miniflux.*
    ExecStart=
    ExecStart=systemd-nspawn --quiet --keep-unit --register=yes --boot --network-veth -U \
            --settings=override --machine=%i \
            --load-credential=miniflux.admin-username:miniflux.admin-username \
            --load-credential=miniflux.admin-password:miniflux.admin-password

As root, the drop-in goes in `/etc/systemd/system/`, and the system unit's
`ExecStart=` has `--link-journal=try-guest` instead of `--register=yes`.
`ImportCredential=` reads the credentials from a credstore: `/etc/credstore/`
for the system, `~/.config/credstore/` or `$XDG_RUNTIME_DIR/credstore/` for a
user, and their `credstore.encrypted/` counterparts for files encrypted with
`systemd-creds [--user] encrypt`:

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
foreign UID range, which is what unprivileged `systemd-nspawn` requires. Build,
`mkosi boot`, `bin/install-app` and the user's `systemd-nspawn@.service` need
no privileges.

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
