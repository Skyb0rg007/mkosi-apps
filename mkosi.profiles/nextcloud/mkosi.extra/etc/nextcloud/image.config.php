<?php
// Nextcloud's settings for this image. nextcloud-setup.service links every
// /etc/nextcloud/*.config.php into Nextcloud's configuration directory,
// /var/lib/nextcloud/config, where they override config.php; a confext can add
// more. Nextcloud writes config.php itself, from the web UI and occ.
$CONFIG = [
	// The release in /usr is read-only; apps from the app store go to /var.
	'apps_paths' => [
		['path' => '/usr/share/nextcloud/apps', 'url' => '/apps', 'writable' => false],
		['path' => '/usr/share/nextcloud/custom_apps', 'url' => '/custom_apps', 'writable' => true],
	],
	'datadirectory' => '/var/lib/nextcloud/data',
	// Upgrades come with the image, and run when it boots.
	'upgrade.disable-web' => true,
	'memcache.local' => '\OC\Memcache\APCu',
	'memcache.distributed' => '\OC\Memcache\Redis',
	'memcache.locking' => '\OC\Memcache\Redis',
	'redis' => ['host' => 'localhost', 'port' => 6379],
	// Background jobs' expensive tasks between 01:00 and 05:00 UTC.
	'maintenance_window_start' => 1,
];
