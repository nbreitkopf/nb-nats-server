# NATS Server

A single NATS server with JetStream, deployed to [Dokploy](https://dokploy.com) via Docker Compose.
Clients connect over **secure WebSocket (`wss://`)**, with TLS terminated by Traefik behind Cloudflare.

## Files

| File | Purpose |
|---|---|
| `nats.conf` | Server configuration (ports, limits, auth, WebSocket, JetStream) |
| `Dockerfile` | Bakes `nats.conf` into a `nats:<version>-alpine` image |
| `docker-compose.yml` | Service definition used by Dokploy |
| `.env` | Local secrets — **not committed** (see `.gitignore`) |
| `.dockerignore` | Keeps `.env`, `.git`, `.vscode` out of the build context |

## Architecture

```
client ──wss://<domain>──▶ Cloudflare (proxied, SSL mode "Full")
                              │ HTTPS :443
                              ▼
                       Traefik (Dokploy, Let's Encrypt cert)
                              │ ws :8080 via dokploy-network
                              ▼
                       nats container
                         4222  client port   (internal only)
                         8080  WebSocket     (routed by the Dokploy domain)
                         8222  monitoring    (internal only — never publish)
                         /data  JetStream storage (volume: nats-data)
```

- **Auth:** a single user `main`. Its password comes from the `NATS_MAIN_TOKEN` environment variable.
- **JetStream:** `store_dir: /data`. NATS creates `/data/jetstream` itself. The data is kept in the `nats-data` volume.
- **Config changes:** because `nats.conf` is copied into the image, pushing a change to it builds a new image. Dokploy then recreates the container on deploy. Pushes that don't touch the config don't restart the server.

## Configuration

### Environment variables

| Variable | Description |
|---|---|
| `NATS_MAIN_TOKEN` | Password for user `main`. Generate with `openssl rand -hex 32`. |

Set it in Dokploy under the service's **Environment** tab. For local runs, put it in `.env`.

### Server settings

Edit `nats.conf`, then commit and push. To upgrade NATS, change the version in the `FROM` line of the `Dockerfile`.

## Deploying on Dokploy

1. Create a **Compose** service with **Git** as the source (this repo, `docker-compose.yml`).
2. Set `NATS_MAIN_TOKEN` in **Environment**.
3. Add a **Domain**:
   - Container port: **8080**
   - HTTPS: **on**, certificate: None (using Cloudflare's proxy, so no Let's Encrypt is needed)
4. In Cloudflare, proxy the DNS record and set SSL/TLS mode to **Full**.
   - For **Full (strict)**, use a Cloudflare Origin Certificate in Dokploy instead of Let's Encrypt.
   - Enable **Always Use HTTPS** only after the certificate has been issued.
5. Deploy.

The service must be on the external `dokploy-network` (already set in `docker-compose.yml`), or Traefik can't reach it.

## Connecting

Install the [NATS CLI](https://github.com/nats-io/natscli/releases) (`go install github.com/nats-io/natscli/nats@latest`), then save a context:

```sh
nats context save nb-nats-main "wss://nats.nbapps.dev" --user main --password "<NATS_MAIN_TOKEN>" --select
```

```sh
nats server check connection
nats sub "test.>"                 # terminal 1
nats pub test.hello "hi"          # terminal 2
nats stream ls
```

From application code, use any NATS client that supports WebSocket, with URL `wss://nats.nbapps.dev` (port 443 by default) and the same user and password.

> Don't use `ws://` — the password would cross the internet in plain text.

## Operations

The image is Alpine based and has **no `bash`**. In Dokploy's terminal, choose **`sh`**.

| Task | How |
|---|---|
| Logs | Dokploy → service → **Logs** |
| Health | `wget -qO- http://localhost:8222/healthz` (inside the container) |
| Server info / start time | `wget -qO- http://localhost:8222/varz \| grep '"start"'` |
| JetStream status / store dir | `wget -qO- http://localhost:8222/jsz` |
| Restart | Dokploy **Stop** → **Deploy**, or `docker restart <container>` on the host |

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `invalid websocket connection` | Service not on `dokploy-network`, wrong container port (must be 8080), or HTTPS off on the Dokploy domain while Cloudflare is in Full mode |
| `ws://` works, `wss://` doesn't | Cloudflare is in Full mode but the Dokploy domain has HTTPS off |
| Authorization error / server won't start | `NATS_MAIN_TOKEN` not set in Dokploy (check the logs for "variable reference … can not be found") |
| `exec: "bash": executable file not found` | Use `sh` instead of `bash` |
| `nats server info` → no responders | Needs a system-account user, which isn't configured. Use the `:8222` monitoring endpoints instead. |
