# UnrealIRCd Docker Stack

This repository builds a self-contained UnrealIRCd server image, provisions TLS certificates via Let's Encrypt, and wires configuration through environment variables so deployments stay reproducible.

## Prerequisites
- Docker 24+ and Docker Compose V2
- Ports 6697 (IRC over TLS) and 80 (HTTP-01 challenge) reachable from the public internet
- DNS `A/AAAA` record for `${IRCDOMAIN}` pointing at the host where this stack runs

## Configuration
1. Copy `.env.example` to `.env` and update the values:
   - `DOMAIN`: network/domain label used inside UnrealIRCd notices (e.g., `example.org`).
   - `IRCDOMAIN`: public DNS hostname clients will connect to (e.g., `irc.example.org`). This value is used for the certificate request and the `me { name }` block.
   - `OPERNAME`: operator account name injected into `oper` block.
   - `OPERPASS`: strong password for the operator.
   - `LETSENCRYPT_EMAIL`: email used for certificate registration and expiry alerts.
   - *(Optional)* `CLOAKKEY1-3`: override the automatically generated cloak keys (defaults are random 80–100 character alphanumeric strings).
2. Review `conf/unrealircd.conf` to tweak network-specific settings. The file contains `${DOMAIN}`, `${IRCDOMAIN}`, `${OPERNAME}`, and `${OPERPASS}` placeholders that are substituted at runtime; you can add additional environment variables following the same `${VAR}` pattern.

## Building and running
```bash
cp .env.example .env
# edit .env before continuing
sudo docker compose build
sudo docker compose up -d
```

The entrypoint performs these steps on every boot:
1. Validates required environment variables and auto-generates 80–100 character alphanumeric cloak keys if they aren't supplied.
2. Obtains or renews the Let's Encrypt certificate for `${IRCDOMAIN}` using the standalone HTTP-01 challenge (port 80 must be free).
3. Copies `conf/unrealircd.conf` into the container data volume after running `envsubst`, then starts UnrealIRCd in the foreground via `gosu` as the non-root `unreal` user.

### Renewals & persistence
- Certificates live under the `letsencrypt` named volume (`/etc/letsencrypt`) so they persist between restarts.
- The entire UnrealIRCd installation (`/opt/unrealircd/unrealircd`) is stored in the `unrealircd-data` volume; upgrade the stack by rebuilding the image and re-running `docker compose up -d`.

## Troubleshooting
- If `certbot` fails, check that the DNS record for `${IRCDOMAIN}` resolves to the host and that no other service binds to port 80.
- View container logs with:
```bash
sudo docker compose logs -f unrealircd
```
- To force certificate re-issuance, delete the `letsencrypt` volume: `sudo docker volume rm unrealircd_letsencrypt` (compose namespace may vary).
