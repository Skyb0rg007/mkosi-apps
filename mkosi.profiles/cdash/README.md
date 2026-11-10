# cdash

[CDash](https://www.cdash.org/), the dashboard that CTest submits build and
test results to, with a local PostgreSQL. nginx and PHP-FPM serve it on port
80; a queue worker processes the submissions. Its database is in the
machine's PostgreSQL, the submitted files in `/var/lib/cdash/storage/`.

## Build

Upstream publishes releases only as git tags and the container image
`kitware/cdash`, whose build installs CDash's PHP dependencies with composer
and builds its web client with npm. `mkosi.sync` takes the layers of that
image that hold `/cdash`, pinned by digest, which is their checksum, and
leaves out `node_modules/`, which only built the web client, and the tests.
PHP is Debian's 8.4, the version upstream's image has.

## First steps

There are no accounts at first. Create an admin from the machine's shell:

    cdash user:save --email=admin@example.com --password=… --admin=1

`cdash` is `php artisan` as the `cdash` user, with CDash's settings, for
CDash's other commands too. Log in, create a project, and point CTest at it,
in the project's `CTestConfig.cmake`:

    set(CTEST_SUBMIT_URL "http://cdash._dhcp/submit.php?project=MyProject")

## Configuration

CDash reads environment variables, from `/etc/cdash.conf` if it exists (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
which override the image's in `/usr/lib/cdash/cdash.env`, e.g.:

    APP_URL=https://cdash.example.com
    USER_REGISTRATION_FORM_ENABLED=false
    MAIL_MAILER=smtp
    MAIL_HOST=smtp.example.com
    MAIL_FROM_ADDRESS=cdash@example.com

Then `systemctl restart php8.4-fpm cdash-worker`. `APP_URL` is the URL CDash
puts in its links and emails, `http://cdash._dhcp` by default. Upstream's
[configuration documentation](https://github.com/Kitware/CDash/blob/master/docs/config.md)
lists the rest, logins through GitHub, GitLab, LDAP or SAML included.

## Notes

- `cdash-secret.service` generates Laravel's application key once, into
  `/var/lib/cdash-secret/`, which encrypts sessions and cookies.
- `cdash-setup.service` runs the database migrations on every boot, as
  upstream's image does as it starts, so an upgrade migrates on its first
  boot. It caches the views and the GraphQL schema, in `/var/cache/cdash/`,
  but not the configuration or the routes as upstream does: those would keep
  `/etc/cdash.conf`'s old settings until the next boot.
- `cdash-schedule.timer` runs Laravel's scheduler every minute, for the
  hourly and daily pruning of old builds, files and tokens that upstream's
  image runs with `schedule:work`.
- CDash logs to the journal, through syslog, as `c-dash`:
  `journalctl -t c-dash`, or `-u cdash-worker` for the submissions it
  processed. A rejected submission also logs "Failed to move … from inbox/ to
  failed/", which upstream's does too.
- nginx sets no limit on uploads, as upstream's Apache does not: CTest
  submits whole logs and files in one request.
