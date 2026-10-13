
# mkosi-apps

Minimal [mkosi](https://mkosi.systemd.io/) images for single applications, each
run as its own `systemd-nspawn` container, without root.

| App | |
|---|---|
| [homebox](mkosi.profiles/homebox/README.md) | Homebox inventory manager |
| [jellyfin](mkosi.profiles/jellyfin/README.md) | Jellyfin media server |
| [karakeep](mkosi.profiles/karakeep/README.md) | Karakeep bookmark manager, with Meilisearch and headless Chromium |
| [miniflux](mkosi.profiles/miniflux/README.md) | Miniflux feed reader, with PostgreSQL |
| [netbox](mkosi.profiles/netbox/README.md) | NetBox, with PostgreSQL and Redis |
| [nextcloud](mkosi.profiles/nextcloud/README.md) | Nextcloud server, with PostgreSQL and Redis |
| [paperless](mkosi.profiles/paperless/README.md) | Paperless-ngx document management, with Redis |
| [soju](mkosi.profiles/soju/README.md) | soju IRC bouncer, with the gamja web client |
| [victoriametrics](mkosi.profiles/victoriametrics/README.md) | VictoriaMetrics, with vmagent, vmalert and vmauth |
| [victorialogs](mkosi.profiles/victorialogs/README.md) | VictoriaLogs |
| [wakapi](mkosi.profiles/wakapi/README.md) | Wakapi coding statistics |

How it all fits together, and why, is in [docs/design.md](docs/design.md).

## Building

Each app is a profile in `mkosi.profiles/<app>/`, built on top of
`mkosi.images/minimal-base`. Apps that need PostgreSQL, Redis, nginx or a
Python virtualenv include them from `mkosi.include/`. Run mkosi from the dev
shell (`nix develop`):

    mkosi --profile=soju build          # mkosi.output/soju_0.10.1-1/
    mkosi --profile=soju boot           # try it, on a throwaway copy
    mkosi --profile=soju,vm build       # a VM disk, in mkosi.output/vm/

`mkosi boot` names the machine after the app, like an installed one, which has
to be stopped first.

An app's version is in `mkosi.profiles/<app>/mkosi.version` as
`<upstream>-<revision>`. For a new upstream release, set its version with
revision `1` and update the checksum in the app's `mkosi.sync`; for any other
change to the image, bump the revision.

## Running

`bin/install-app` installs a build as its app's machine, for the user's
`systemd-nspawn@.service`, or, as root, for the system's:

    bin/install-app mkosi.output/soju_0.10.1-1
    systemctl --user enable --now systemd-nspawn@soju.service  # as root: no --user

    # Upgrade
    bin/install-app mkosi.output/soju_0.10.2-1
    systemctl --user restart systemd-nspawn@soju.service

The machine is `~/.local/state/machines/<app>.mstack/` (as root,
`/var/lib/machines/`): the image provides `/usr`, read-only, and everything
else, the app's data included, lives in its `root/`. An app is reached from
the host as `<app>._dhcp`, on its usual ports, or as `<app>`, through
`nss-mymachines`; Django apps (netbox, paperless) refuse the former. Then
`machinectl [--user] shell <app>` gives a root shell in it.

To roll back, rename the newest version in `layer@0.v/` to a name it ignores,
e.g. `.layer@0_0.10.2-1.old`, and restart. Apps migrate their data on start,
so a rollback past a schema change needs a backup of `root/`. The versions are
owned by the foreign UID range; as root `rm -rf` deletes one, otherwise:

    mkosi-sandbox --ro-bind / / --tmpfs /tmp --bind-foreign "$dir" /tmp/dir \
        --become-root -- find /tmp/dir -mindepth 1 -delete && rmdir "$dir"

An app can also run as a VM, from the `vm` profile's disk image, which
updates itself from a server through `systemd-sysupdate`, with A/B partitions;
see [docs/vm.md](docs/vm.md).

## Configuring

### Changing an app's configuration

A machine's `/etc` starts out with the image's defaults. Changes come as
configuration extensions, which `systemd-confext` merges over `/etc` on boot: a
directory, or a `.raw` image, in `/var/lib/confexts/` or `/run/confexts/`, with
a release file named after it. Its files replace or add to those in `/etc`:

    machinectl [--user] shell victoriametrics
    d=/var/lib/confexts/local
    mkdir -p $d/etc/extension-release.d $d/etc/victoriametrics/rules
    echo ID=_any > $d/etc/extension-release.d/extension-release.local
    # add $d/etc/victoriametrics/rules/*.yml, ...
    systemctl restart systemd-confext
    systemctl restart victoria-metrics vmalert  # or reload, or start, ...

Use `systemctl restart systemd-confext`, not `systemd-confext refresh`, which
would leave `/etc` read-only. A file from a confext no longer follows the image
on upgrades.

### Credentials

Some settings, secrets in particular, come as system credentials. nspawn only
passes on those named with `--load-credential=`, so they go in a drop-in that
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

`ImportCredential=` reads them from `~/.config/credstore/` (as root,
`/etc/credstore/`), or encrypted from `credstore.encrypted/` (see
`systemd-creds [--user] encrypt`). List only credentials that exist: a missing
one stops the container from starting. As root, the drop-in goes in
`/etc/systemd/system/`, and the system unit's `ExecStart=` has
`--link-journal=try-guest` instead of `--register=yes`.

## Host setup

mkosi bootstraps its Debian tools tree with the host's apt, which reads the
archive keyring from exactly `/usr/share/keyrings/debian-archive-keyring.gpg`.
The host's systemd-networkd serves the containers DHCP, which its firewall has
to accept. On NixOS:

    systemd.tmpfiles.rules = [
      "L+ /usr/share/keyrings/debian-archive-keyring.gpg - - - - ${pkgs.debian-archive-keyring}/share/keyrings/debian-archive-keyring.gpg"
    ];
    networking.firewall.trustedInterfaces = [ "ns-+" ];
