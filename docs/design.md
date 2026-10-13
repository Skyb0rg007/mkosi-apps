# How mkosi-apps works

The why behind the [README](../README.md): what the machines are made of, and
the constraints of running them without privileges.

## Machines

`bin/install-app` installs a build as a mount stack
([systemd.mstack(7)](https://www.freedesktop.org/software/systemd/man/latest/systemd.mstack.html))
that `systemd-nspawn@<app>.service` finds by machine name:

    ~/.local/state/machines/soju.mstack/
    ├── layer@0.v/layer@0_0.10.1-1/   builds; the newest's /usr is booted
    ├── layer@0.v/layer@0_0.10.2-1/
    ├── layer@1/                      empty, see below
    └── root/                         the container's /etc, /var, ...

Only `/usr` comes from the image, read-only and versioned. Everything else
belongs to the machine, in `root/`: its `/etc` starts out empty and is
populated on the first boot (see [/usr is enough to boot](#usr-is-enough-to-boot)),
and its `/var` holds the app's data.

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
- A machine from before `root/` has its `/var` in `bind@var/`, which
  `bin/install-app` moves to `root/var/`, together with the users and groups
  of the version the machine ran: Debian's postinsts allocate some of them,
  such as PostgreSQL's, at IDs that `systemd-sysusers` would not give out
  again.
- `bin/install-app` refuses an output that has been booted, which leaves
  state behind in it, such as a machine ID that would take precedence over
  `MachineID=`. `mkosi -f build` replaces it.
- A new machine gets the profile's `<app>.nspawn` settings, with a machine ID
  of its own, in `~/.config/systemd/nspawn/` or `/etc/systemd/nspawn/`.
  Settings there are trusted, unlike a file next to the image. The first boot
  writes that machine ID to the machine's `/etc/machine-id`.
- The machine keeps its users in its own `/etc/passwd`, so they keep their
  IDs across image versions; `systemd-sysusers` adds new ones.
- The settings leave out the root autologin of `mkosi.nspawn`.
- The settings forward no ports. `Port=` needs root, and forwards
  connections to the host's addresses, but not to `127.0.0.0/8`; the host side
  of the veth needs configuring, e.g. by systemd-networkd's
  `80-container-ve.network`.
- The apps listen on their services' standard ports, e.g. 80 for HTTP.
  Services that do not run as root get `CAP_NET_BIND_SERVICE` for that.

## /usr is enough to boot

Following [ParticleOS](https://github.com/systemd/particleos), the images'
`/usr` carries everything needed to boot with an empty `/etc`:

- `mkosi.finalize` copies each image's `/etc` to `/usr/share/factory/etc`, and
  `tmpfiles.d/etc.conf` in minimal-base, plus a file per app for its own
  configuration, symlinks entries of it into `/etc`. Being links, they follow
  the image on upgrades; a confext overrides them. Apps whose directories a
  confext may add files to (soju, VictoriaMetrics) are linked file by file,
  since a confext's directory hides a lower layer's link to a whole directory.
- `systemd-sysusers` creates the users, Debian's `www-data` included.
- minimal-base's own files are copied again into every app image, after the
  app's packages: those can upgrade minimal-base's packages, which would
  overwrite files it replaces, such as systemd's `tmpfiles.d/etc.conf`.
- `libnss-myhostname` resolves `localhost` without an `/etc/hosts`, before
  `systemd-resolved` runs, and `libnss-systemd` the users of `DynamicUser=`;
  Debian's `nsswitch.conf` names both, but only their packages provide them.
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

## Writable confexts

Merging a confext makes `/etc` read-only by default. minimal-base's drop-in for
`systemd-confext.service` keeps it writable, with writes landing in
`/var/lib/extensions.mutable/etc/`, above the confexts, which are above the
machine's own `/etc`. systemd's default mount options for that include
`redirect_dir=on`, which overlayfs refuses in a user namespace, as in these
containers; the drop-in sets `userxattr,noatime,metacopy=off,index=off`
through `SYSTEMD_CONFEXT_OVERLAYFS_MOUNT_OPTIONS` instead. A plain
`systemd-confext refresh` lacks these settings and merges read-only.

## systemd from OBS

The images take systemd from its stable branch built for trixie on
[OBS](https://build.opensuse.org/project/show/system:systemd:stable), through
`mkosi.sandbox/`, as ParticleOS can: `SYSTEMD_CONFEXT_OVERLAYFS_MOUNT_OPTIONS`
needs systemd 259, and trixie has 257. Its `debian.conf` copies a two-file
`/etc/pam.d` from its own factory, which would hide Debian's PAM
configuration, so the top-level `mkosi.postinst.chroot` drops that line, as
ParticleOS does, in every app image, since an app's packages can upgrade
systemd's.
A change to the repository's packages takes `mkosi -ff build`, since the
incremental cache otherwise keeps the packages it has.

## Rootless containers

An app is built as a directory (`Format=directory`) owned by the systemd
foreign UID range, which is what unprivileged `systemd-nspawn` requires. Build,
`mkosi boot`, `bin/install-app` and the user's `systemd-nspawn@.service` need
no privileges.

`ForeignUIDRange=yes` makes mkosi shift the finished tree itself with
`systemd-dissect --shift`, inside a user namespace `systemd-nsresourced` maps
the foreign range into. No polkit check is involved, and the next
`mkosi -f build` removes the foreign-owned tree on its own. The shift needs
systemd 258 or newer in the tools tree, which is why that tree tracks Debian
testing.

`systemd-nspawn --image=` on a `Format=disk` output has to go through
`systemd-mountfsd`, which fails unprivileged with
`io.systemd.InteractiveAuthenticationRequired`, an admin prompt. Only the
foreign-owned directory avoids that.

mkosi builds in single-UID mode, so every inode is owned by the invoking user
before the shift and by foreign UID 0 after it. Files that a package would
install owned by a service user land as root instead; use `StateDirectory=` or
tmpfiles `z`/`Z` where that matters.

## Source builds

App sources are fetched online and built offline, the split
[tine](https://github.com/amutable-systems/tine) uses. An image's `mkosi.sync`
downloads and verifies the release, then resolves its dependencies into a
cache under `mkosi.cache/` against the project's own lockfile. Its build
script runs without network and reads only that cache. For Go (`soju`) the
cache is go's module proxy layout, served to the build as `GOPROXY=file://…`
with `-mod=readonly`. The tools tree's `golang-go` fetches (sync scripts run
there); the image's own `golang-go` from `BuildPackages=` compiles.

## Host setup details

- mkosi runs directly from the dev shell, not wrapped in `buildFHSEnv`: inside
  bubblewrap's user namespace `systemd-nsresourced` refuses the range mkosi
  asks for at startup (`DynamicRangeUnavailable`).
- `mkosi.tools.conf/mkosi.prepare` gives the tools tree an `/etc/static`
  symlink so that NixOS's `/etc/resolv.conf` resolves inside mkosi's
  sandboxes; without it, go in a sync script cannot look up hosts. The script
  explains the details.
