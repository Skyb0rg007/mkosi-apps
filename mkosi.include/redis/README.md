# redis

A local Redis, from Debian's `redis-server`, for the apps that include this
directory from their profile (`Include=%D/mkosi.include/redis`). It listens on
`localhost:6379`, keeps its data in `/var/lib/redis/`, and is configured by
Debian's `/etc/redis/redis.conf`.

The package's postinst gives `/etc/redis` to the `redis` group, which mkosi's
single-UID build cannot, so this makes Debian's configuration, which holds no
secrets, readable to all instead. A confext that adds a password to it has to
keep that in mind.
