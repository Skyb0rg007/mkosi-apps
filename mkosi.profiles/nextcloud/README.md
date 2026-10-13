# nextcloud

[Nextcloud](https://nextcloud.com/) server, from upstream's release tarball,
verified against Nextcloud's signing key (`nextcloud.asc`) and its checksum in
`mkosi.sync`. nginx serves it on port 80 with PHP-FPM, from Nextcloud's own
nginx configuration, with a local PostgreSQL
([mkosi.include/postgresql](../../mkosi.include/postgresql/README.md)) and
Redis ([mkosi.include/redis](../../mkosi.include/redis/README.md)) for file
locking and caching. Background jobs run from `nextcloud-cron.timer`.

On the first visit, Nextcloud's installer asks for an admin account; the
database is filled in already. The host name it is installed under becomes its
trusted domain; others are added with `occ` or a confext (see below).

The release stays read-only in `/usr/share/nextcloud`. Everything Nextcloud
writes is in `/var/lib/nextcloud/`: its configuration in `config/`, the files
in `data/`, apps from the app store in `custom_apps/`.

## Configuration

`occ` runs Nextcloud's `occ` as the `nextcloud` user, e.g.:

    machinectl [--user] shell nextcloud /usr/bin/occ config:system:set default_phone_region --value=DE

Nextcloud writes its `config.php` itself. Settings can also come from
`*.config.php` files in `/etc/nextcloud/`, which a confext adds (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration))
and which override `config.php`; `nextcloud-setup.service` links them into the
configuration directory, so restart it and `php8.4-fpm` afterwards. For a
proxy in front:

    <?php
    $CONFIG = [
        'trusted_domains' => ['cloud.example.com'],
        'overwrite.cli.url' => 'https://cloud.example.com',
        'overwriteprotocol' => 'https',
        'trusted_proxies' => ['192.168.1.1'],
    ];

Nextcloud copies such settings into `config.php` when it writes it, so a
setting removed from a confext stays until it is removed with `occ` as well.
The image's own settings are in `/etc/nextcloud/image.config.php`. PHP's
configuration is `/etc/php`, linked as a whole, so a confext changing it has to
carry all of it.

## Upgrades

`nextcloud-setup.service` runs `occ upgrade` and adds missing database
columns, indices and keys when the image has a new release. Nextcloud only
upgrades from the previous major release or the same one, so a machine can't
skip a major release. Its web updater is disabled: upgrades come with the
image. After an upgrade, or on a new installation, the setup checks in the
admin settings may ask for `occ maintenance:repair --include-expensive`.

## Notes

- PHP-FPM runs Nextcloud's own pool as the `nextcloud` user, which owns its
  configuration, so `occ` and `cron.php` run as that user as well.
- `custom_apps` in the release is a link to `/var/lib/nextcloud/custom_apps`,
  for nginx to serve the apps' files. Nextcloud's integrity check, which flags
  any other change to the release, skips its app directories.
