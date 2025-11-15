# UnrealIRCd Docker Stack

This repository builds a self-contained UnrealIRCd server image, provisions TLS certificates via Let's Encrypt, and wires configuration through environment variables so deployments stay reproducible.

## Prerequisites
- Docker 24+ and Docker Compose V2
- Ports 6697 (IRC over TLS) and 80 (HTTP-01 challenge) reachable from the public internet
- For HTTP-01: DNS `A/AAAA` record for `${IRCDOMAIN}` pointing at the host where this stack runs
- For DNS-01: Provider API credentials (Cloudflare/DigitalOcean) via a credentials file or API token in env

## Configuration
1. Copy `.env.example` to `.env` and update the values:
   - `DOMAIN`: network/domain label used inside UnrealIRCd notices (e.g., `example.org`).
   - `IRCDOMAIN`: public DNS hostname clients will connect to (e.g., `irc.example.org`). This value is used for the certificate request and the `me { name }` block.
   - `OPERNAME`: operator account name injected into `oper` block.
   - `OPERPASS`: strong password for the operator.
   - `LETSENCRYPT_EMAIL`: email used for certificate registration and expiry alerts.
   - `CERTBOT_CHALLENGE` (optional): either `http-01` (default) or `dns-01`.
   - `CERTBOT_DNS_PLUGIN` (dns-01): `cloudflare` or `digitalocean` (baked-in).
   - `CERTBOT_DNS_CREDENTIALS` (dns-01, option A): path inside the container to the plugin credentials file (e.g., `/run/secrets/cloudflare.ini`).
   - `DNS_CLOUDFLARE_API_TOKEN` (dns-01, option B): Cloudflare API token provided directly via env; no file mount needed.
   - `DNS_DIGITALOCEAN_TOKEN` (dns-01, option B): DigitalOcean API token provided directly via env; no file mount needed.
   - `CERTBOT_DNS_PROPAGATION_SECONDS` (dns-01, optional): DNS propagation wait, default `60`.
   - *(Optional)* `CLOAKKEY1-3`: override the automatically generated cloak keys (defaults are random 80–100 character alphanumeric strings).
2. Review `conf/unrealircd.conf` to tweak network-specific settings. The file contains `${DOMAIN}`, `${IRCDOMAIN}`, `${OPERNAME}`, and `${OPERPASS}` placeholders that are substituted at runtime; you can add additional environment variables following the same `${VAR}` pattern.

## Building and running
```bash
cp .env.example .env
# edit .env before continuing

# If using DNS-01 with credentials file (option A), e.g. Cloudflare:
# mkdir -p secrets && printf "dns_cloudflare_api_token=YOUR_TOKEN\n" > secrets/cloudflare.ini
# chmod 600 secrets/cloudflare.ini

sudo docker compose build
sudo docker compose up -d
```

The entrypoint performs these steps on every boot:
1. Validates required environment variables and auto-generates 80–100 character alphanumeric cloak keys if they aren't supplied.
2. Obtains or renews the Let's Encrypt certificate for `${IRCDOMAIN}` using:
   - HTTP-01 standalone challenge if `CERTBOT_CHALLENGE=http-01` (port 80 must be free), or
   - DNS-01 via the selected plugin if `CERTBOT_CHALLENGE=dns-01` (no port 80 required).
3. Copies `conf/unrealircd.conf` into the container data volume after running `envsubst`, then starts UnrealIRCd in the foreground via `gosu` as the non-root `unreal` user.

### Renewals & persistence
- Certificates live under the `letsencrypt` named volume (`/etc/letsencrypt`) so they persist between restarts.
- The entire UnrealIRCd installation (`/opt/unrealircd/unrealircd`) is stored in the `unrealircd-data` volume; upgrade the stack by rebuilding the image and re-running `docker compose up -d`.

## Troubleshooting
- If `certbot` fails:
   - HTTP-01: ensure `${IRCDOMAIN}` resolves to the host and that no service binds to port 80.
   - DNS-01: ensure the credentials file is mounted into the container and valid; adjust `CERTBOT_DNS_PROPAGATION_SECONDS` if needed.

### DNS-01 quickstart
- Cloudflare (env token): set `CERTBOT_CHALLENGE=dns-01`, `CERTBOT_DNS_PLUGIN=cloudflare`, `DNS_CLOUDFLARE_API_TOKEN=...`. No file mount needed.
- DigitalOcean (env token): set `CERTBOT_CHALLENGE=dns-01`, `CERTBOT_DNS_PLUGIN=digitalocean`, `DNS_DIGITALOCEAN_TOKEN=...`. No file mount needed.
- Credentials file option: alternatively set `CERTBOT_DNS_CREDENTIALS=/run/secrets/<provider>.ini` and mount it; the INI must contain the appropriate `dns_<provider>_...` key.
- View container logs with:
```bash
sudo docker compose logs -f unrealircd
```
- To force certificate re-issuance, delete the `letsencrypt` volume: `sudo docker volume rm unrealircd_letsencrypt` (compose namespace may vary).
