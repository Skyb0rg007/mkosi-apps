# jellyfin

The [Jellyfin](https://jellyfin.org/) media server, from upstream's Debian
packages for trixie (server, web client and its own ffmpeg), pinned by
checksum in `mkosi.sync`. Its web UI is on port 80, where the setup wizard
creates the first user.

Jellyfin keeps everything it writes in `/var`: its database and metadata in
`/var/lib/jellyfin/`, its settings in `/var/lib/jellyfin/config/`, its
transcodes and images in `/var/cache/jellyfin/`.

## Media

The media has to be inside the machine: these containers cannot bind host
directories, and Jellyfin cannot mount network shares itself. A library in,
for example, `/srv/media` comes in by unpacking a tar stream as the machine's
root, readable by the `jellyfin` user:

    tar -C ~/Videos -c --mode=a+rX . |
        mkosi-sandbox --ro-bind / / --tmpfs /tmp \
            --bind-foreign ~/.local/state/machines/jellyfin.mstack/root /tmp/root \
            --become-root -- sh -c 'mkdir -p /tmp/root/srv/media &&
                tar -C /tmp/root/srv/media -x --no-same-owner'

Run this from the dev shell, which provides `mkosi-sandbox`. As root, the
machine is in `/var/lib/machines/`, and plain `tar` writes there directly.

## Configuration

Settings are made in the web UI, under Dashboard. Service options, such as
`JELLYFIN_ADDITIONAL_OPTS`, are in `/etc/default/jellyfin`, which a confext
can replace (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)).

## Notes

- Jellyfin takes its HTTP port only from its network settings, so
  `tmpfiles.d/jellyfin.conf` creates `network.xml` with port 80 before the
  first start. Changing the port in the dashboard is kept from then on.
- The configuration directory is `/var/lib/jellyfin/config/` rather than
  Debian's `/etc/jellyfin/`, as in upstream's container image, because
  Jellyfin writes it from the web UI.
- Hardware transcoding would need a GPU's `/dev/dri` in the container, which
  needs a privileged nspawn setting. The `jellyfin` user is in the `render`
  and `video` groups for when one is there.
