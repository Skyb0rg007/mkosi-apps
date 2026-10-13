
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
configuration lives in `/var` with their data, also when `mkosi boot` runs the
image with its own `/etc`.

A major PostgreSQL upgrade needs one image with both server versions installed,
so that `pg_upgradecluster` can migrate the old cluster.

Miniflux runs its migrations on every start and listens on `0.0.0.0:80`
unless `miniflux.conf` says otherwise:

    mkosi --profile=miniflux \
        --credential=miniflux.admin-username=admin \
        --credential=miniflux.admin-password=… \
        boot

### soju

soju listens for IRC in plain text on port 6667 (`irc+insecure://`). nginx
serves the [gamja](https://codeberg.org/emersion/gamja) web client in plain
HTTP on port 80 and proxies gamja's WebSocket to soju's `http+unix://` socket,
as in soju's `contrib/nginx.md`. soju runs as group `www-data` so that nginx
can connect to that socket.

Neither does TLS: that is up to a proxy in front, which holds the certificate,
e.g. nginx with the `stream` server from `contrib/nginx.md` for IRC and an
HTTPS server for gamja. The proxy must not send the PROXY protocol, which soju
only accepts from addresses listed in `accept-proxy-ip`, so soju sees the
proxy's address as every client's.

Users are created with `sojuctl`:

    machinectl [--user] shell soju /usr/bin/sojuctl user create -username … -password …

gamja's release is its unbundled source, which runs as is once its
`node_modules/` exist. The sync script fetches the runtime dependencies that
its `package-lock.json` pins, checked against the lockfile's hashes, so the
image needs neither npm nor a build. gamja's version is pinned in the sync
script, separately from soju's.

### victoriametrics

Single-node [VictoriaMetrics](https://docs.victoriametrics.com/victoriametrics/)
with its vmui web UI on port 80, plus upstream's vmutils. It scrapes its own
metrics every 10s from the start. Everything else is configured with files in
`/etc/victoriametrics/`, all optional:

| File | Effect |
|---|---|
| `scrape.yml` | Prometheus `scrape_configs` for VictoriaMetrics to scrape |
| `vmagent.yml` | Run vmagent (port 8429) with these `scrape_configs`, writing into VictoriaMetrics |
| `rules/*.yml` | Run vmalert (port 8880) with these alerting and recording rules; vmui shows its alerts |
| `vmauth.yml` | Run vmauth (port 8427) with this auth config |
| `victoria-metrics.env`, `vmagent.env`, `vmalert.env`, `vmauth.env` | Flags as environment variables, `-retentionPeriod=1y` as `retentionPeriod=1y`; they replace the units' defaults, lists included |

vmalert stores its alerts' state and its recording rules' results in
VictoriaMetrics. It notifies nobody until `vmalert.env` sets `notifier_url` or
`notifier_config`, together with `notifier_blackhole=false`. Each service
reloads its config files on `systemctl reload`; a changed `.env` file takes a
restart. vmbackup, vmrestore, vmctl and vmalert-tool are there to run by hand,
e.g. a backup into the machine's `/var`:

    machinectl [--user] shell victoriametrics /usr/bin/vmbackup \
        -storageDataPath=/var/lib/victoria-metrics \
        -snapshot.createURL=http://localhost/snapshot/create \
        -dst=fs:///var/backups/victoria-metrics

### victorialogs

Single-node [VictoriaLogs](https://docs.victoriametrics.com/victorialogs/) with
its web UI and ingestion APIs on port 80, plus vlagent and vlogscli. Its flags
come from `/etc/victorialogs/victoria-logs.env` like victoriametrics', e.g.
`retentionPeriod=30d` (the default is 7 days). The host's journal can be
shipped there with `systemd-journal-upload`; the URL needs its port, since
without one it gets the default 19532 appended after the path:

    systemd-journal-upload --url=http://victorialogs._dhcp:80/insert/journald

Both images are upstream's release binaries, pinned by checksum in the sync
scripts; upstream does not sign them. They build with a newer Go than trixie's.

### Changing an app's configuration

A machine's `/etc` is its own (see [Running the apps](#running-the-apps)), with
the image's configuration linked in from `/usr/share/factory/etc`, so that it
follows upgrades. To change some, replace the link with a copy, edit it, and
reload or restart the service:

    machinectl [--user] shell victoriametrics
    rm /etc/victoriametrics
    cp -a /usr/share/factory/etc/victoriametrics /etc/
    # edit /etc/victoriametrics/scrape.yml, rules/*.yml, ...
    systemctl reload victoria-metrics  # or restart, or start vmalert, ...

A copy no longer follows upgrades, so compare it with the factory's after one.
Files that the image does not ship but an app reads if present, such as
`/etc/homebox.conf` or `/etc/victoriametrics/vmalert.env`, only need creating
(in a copied directory, for the latter). Secrets can still come as system
credentials, which the services import as `<app>.*`, for flags and config
fields that take a file path, e.g.
`/run/credentials/vmalert.service/victoriametrics.token`.

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

Only `/usr` comes from the image, read-only and versioned. Everything else
belongs to the machine, in `root/`: its `/etc` starts out empty and is
populated on the first boot (see [/usr is enough to boot](#usr-is-enough-to-boot)),
and its `/var` holds the app's data:

    ~/.local/state/machines/soju.mstack/
    ├── layer@0.v/layer@0_0.10.1-1/   builds; the newest's /usr is booted
    ├── layer@0.v/layer@0_0.10.2-1/
    ├── layer@1/                      empty, see below
    └── root/                         the container's /etc, /var, ...

A machine from before `root/` has its `/var` in `bind@var/`, which
`bin/install-app` moves to `root/var/`, together with the users and groups of
the version the machine ran: Debian's postinsts allocate some of them, such as
PostgreSQL's, at IDs that `systemd-sysusers` would not give out again.

A new machine also gets the profile's `<app>.nspawn` settings, with a machine
ID of its own, in `~/.config/systemd/nspawn/` or `/etc/systemd/nspawn/`.
Settings there are trusted, unlike a file next to the image.

To roll back, rename the newest version to a name `layer@0.v/` ignores, e.g.
`.layer@0_0.10.2-1.old`, and restart. The apps migrate their own data on start,
so a rollback past a schema change needs a backup of `root/`. Versions are
owned by the foreign UID range; as root `rm -rf` deletes one, otherwise:

    mkosi-sandbox --ro-bind / / --tmpfs /tmp --bind-foreign "$dir" /tmp/dir \
        --become-root -- find /tmp/dir -mindepth 1 -delete && rmdir "$dir"

- `layer@1/` keeps `/usr` read-only. A single layer would be bind mounted,
  which systemd 261 leaves writable even though it lists it as read-only, so
  the container could change the image. Two layers become an overlayfs
  without a writable layer, which is read-only.
- `PrivateUsers=managed`, which `.mstack/` requires, takes the container's
  UID range from `systemd-nsresourced`. `systemd-mountfsd` maps the
  foreign-owned directories onto it, so `root/` stays foreign-owned no
  matter which range a boot gets. For a client without privileges, mountfsd
  only mounts a foreign-owned directory whose parent the client owns, so the
  machine directory and `layer@0.v/` stay the user's.
- `bin/install-app` refuses an output that has been booted, which leaves state
  behind in it, such as a machine ID that would take precedence over
  `MachineID=`. `mkosi -f build` replaces it.
- The machine keeps its users in its own `/etc/passwd`, so they keep their
  IDs across image versions; `systemd-sysusers` adds new ones.
- The first boot writes the machine ID that `MachineID=` sets to the
  machine's `/etc/machine-id`.
- The settings leave out the root autologin of `mkosi.nspawn`;
  `machinectl [--user] shell <app>` gives a root shell.
- The settings forward no ports: the apps are reached as `<app>._dhcp`, the
  container's own address, which only resolves and routes on the host. From
  elsewhere, an app needs a proxy on the host, or `Port=` in its settings.
  `Port=` needs root, and forwards connections to the host's addresses, but
  not to `127.0.0.0/8`; the host side of the veth needs configuring, e.g. by
  systemd-networkd's `80-container-ve.network`.
- The apps listen on their services' standard ports, e.g. 80 for HTTP.
  Services that do not run as root get `CAP_NET_BIND_SERVICE` for that.

### Passing credentials

`.nspawn` files cannot pass credentials, and nspawn forwards only those named
with `--load-credential=`, so an app's credentials go in a drop-in that
repeats the unit's `ExecStart=` (see `systemctl [--user] cat
systemd-nspawn@.service`), e.g. for miniflux:

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

### /usr is enough to boot

Following [ParticleOS](https://github.com/systemd/particleos), the images'
`/usr` carries everything needed to boot with an empty `/etc`:

- `mkosi.finalize` copies each image's `/etc` to `/usr/share/factory/etc`, and
  `tmpfiles.d/etc.conf` in minimal-base, plus a file per app for its own
  configuration, symlinks entries of it into `/etc`. Being links, they follow
  the image on upgrades; replacing one with a copy customizes it.
- `systemd-sysusers` creates the users, Debian's `www-data` included.
- The first boot applies the presets, which also switch on units that
  Debian's packages only enable in their postinst; `20-debian.preset` turns
  the unwanted ones off again.
- `systemd-firstboot` does not prompt, since no one is at an app's console.
- Each build's `/usr` keeps its build time, so a new version's is newer than a
  machine's `/etc/.updated`, and `ConditionNeedsUpdate=` reruns
  `ldconfig.service` and the like on the first boot after an upgrade. The dev
  shell unsets the `SOURCE_DATE_EPOCH` that Nix exports, which would clamp
  every build to 1980.

`mkosi boot` runs the whole image, whose own `/etc` is already populated; there
all of this is a no-op.

### Every file is owned by image root

mkosi builds in single-UID mode here, so every inode is owned by the invoking
user before the shift and by foreign UID 0 after it. Files that a package would
install owned by a service user land as root instead; use `StateDirectory=` or
tmpfiles `z`/`Z` where that matters.
