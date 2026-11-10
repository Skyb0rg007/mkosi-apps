# woodpecker

[Woodpecker CI](https://woodpecker-ci.org/), its server and an agent, from
upstream's release binaries, pinned by checksum in `mkosi.sync`. The web UI
and API are on port 80, the gRPC port for agents is 9000, and the database is
SQLite in `/var/lib/woodpecker/`.

## Configuration

Woodpecker reads environment variables, from `/etc/woodpecker.conf` (see
[Changing an app's configuration](../../README.md#changing-an-apps-configuration)),
which override the image's in `/usr/lib/woodpecker/server.env` and
`agent.env`. The server needs a forge to log in with and to take repositories
from, so neither service starts until that file exists. For Forgejo, e.g.
Codeberg, with an OAuth application whose redirect URI is
`<WOODPECKER_HOST>/authorize`:

    WOODPECKER_HOST=https://ci.example.com
    WOODPECKER_FORGEJO=true
    WOODPECKER_FORGEJO_URL=https://codeberg.org
    WOODPECKER_FORGEJO_CLIENT=…
    WOODPECKER_FORGEJO_SECRET=…
    WOODPECKER_ADMIN=your-forge-username
    WOODPECKER_OPEN=false

Then `systemctl start woodpecker-server woodpecker-agent`. `WOODPECKER_HOST` is
the URL the forge calls back, for logins and webhooks, so the forge has to
reach it. Upstream's
[forge documentation](https://woodpecker-ci.org/docs/administration/configuration/forges/overview)
covers GitHub, GitLab, Gitea and the rest.

## Pipelines

The machine's agent uses Woodpecker's
[local backend](https://woodpecker-ci.org/docs/administration/configuration/backends/local):
there is no container engine in an unprivileged container, so steps run as
processes in the machine, as the `woodpecker-agent` user, in
`/var/cache/woodpecker-agent/`. A step's `image:` only names its shell, such
as `bash`, and plugins have to be executables on `PATH`; `plugin-git` is
there, for the clone step, with `git`. The image has little else, so builds
that need compilers or other tools want agents elsewhere, with the Docker
backend, connected to this server's port 9000 with its agent secret, from
`/var/lib/woodpecker-secret/secret.env`.

The local backend does not isolate pipelines from the agent: anyone who can
run a pipeline can read the agent secret. Keep `WOODPECKER_OPEN=false` and
trust the repositories it builds.

## Notes

- `woodpecker-secret.service` generates the agent secret and the server's gRPC
  token key once, into `/var/lib/woodpecker-secret/`, so that agents stay
  registered across restarts and upgrades. Only the server reads the gRPC key.
- The agent reaches the server at `127.0.0.1:9000`, not `localhost`: the
  machine has no `/etc/hosts`, and Woodpecker, in Go, resolves names without
  NSS.
