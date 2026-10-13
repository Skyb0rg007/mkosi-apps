# NetBox's configuration for this image: the local PostgreSQL and Redis, the
# secrets netbox-setup.service generates, and NetBox's data in /var. Settings
# of your own go in /etc/netbox/local_configuration.py, which a confext adds
# and which is read last; see NetBox's configuration documentation at
# /static/docs/configuration/.

ALLOWED_HOSTS = ["*"]

# Debian's cluster from postgresql-setup@netbox.service, over its socket with
# peer authentication.
DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.postgresql",
        "NAME": "netbox",
        "USER": "netbox",
        "HOST": "/run/postgresql",
    },
}

REDIS = {
    "tasks": {"HOST": "localhost", "PORT": 6379, "DATABASE": 0, "SSL": False},
    "caching": {"HOST": "localhost", "PORT": 6379, "DATABASE": 1, "SSL": False},
}


def _secret(name):
    with open(f"/var/lib/netbox/secrets/{name}") as f:
        return f.read().strip()


SECRET_KEY = _secret("secret_key")
API_TOKEN_PEPPERS = {1: _secret("api_token_pepper")}

MEDIA_ROOT = "/var/lib/netbox/media"
REPORTS_ROOT = "/var/lib/netbox/reports"
SCRIPTS_ROOT = "/var/lib/netbox/scripts"

try:
    from local_configuration import *  # noqa: F401,F403
except ModuleNotFoundError as e:
    if e.name != "local_configuration":
        raise
