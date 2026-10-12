
# mkosi-apps

This repo contains minimal mkosi-based images for different applications.

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

The top-level image is built as a directory (`Format=directory`) owned by the
systemd foreign UID range, which is what unprivileged
`systemd-nspawn --directory=` requires. Build and boot need no privileges:

    mkosi build
    systemd-nspawn --directory=mkosi.output/image --boot

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
