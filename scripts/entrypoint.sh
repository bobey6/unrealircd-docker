#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Error: Environment variable $name must be set" >&2
    exit 1
  fi
}

random_cloakkey() {
  local len=$((80 + RANDOM % 21))
  local key
  key=$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${len}")
  # Fallback in the unlikely event head returns nothing
  if [[ -z "${key}" ]]; then
    key=$(openssl rand -hex 50 | cut -c1-${len})
  fi
  printf '%s' "${key}"
}

require_env DOMAIN
require_env OPERNAME
require_env OPERPASS
require_env LETSENCRYPT_EMAIL

if [[ -z "${IRCDOMAIN:-}" ]]; then
  if [[ -n "${HOSTNAME:-}" ]]; then
    IRCDOMAIN="${HOSTNAME}"
  else
    echo "Error: Environment variable IRCDOMAIN must be set" >&2
    exit 1
  fi
fi

export DOMAIN IRCDOMAIN OPERNAME OPERPASS LETSENCRYPT_EMAIL

export CLOAKKEY1="${CLOAKKEY1:-$(random_cloakkey)}"
export CLOAKKEY2="${CLOAKKEY2:-$(random_cloakkey)}"
export CLOAKKEY3="${CLOAKKEY3:-$(random_cloakkey)}"

UNREAL_ROOT="${UNREALIRCD_ROOT:-/opt/unrealircd/unrealircd}"
CONFIG_TEMPLATE_DIR="/opt/bootstrap/conf"
CONFIG_TEMPLATE="${CONFIG_TEMPLATE_DIR}/unrealircd.conf"
TARGET_CONF_DIR="${UNREAL_ROOT}/conf"
TARGET_CONF="${TARGET_CONF_DIR}/unrealircd.conf"
CERT_SOURCE_DIR="/etc/letsencrypt/live/${IRCDOMAIN}"
CERT_TARGET_DIR="${UNREAL_ROOT}/tls-certs"
CHALLENGE_METHOD="${CERTBOT_CHALLENGE:-http-01}"

mkdir -p "${TARGET_CONF_DIR}"
mkdir -p "${CERT_TARGET_DIR}"

if [[ ! -s "${CONFIG_TEMPLATE}" ]]; then
  echo "Missing config template at ${CONFIG_TEMPLATE}. Mount ./conf into /opt/bootstrap/conf or rebuild the image." >&2
  exit 1
fi

if [[ ! -d "${CERT_SOURCE_DIR}" || ! -f "${CERT_SOURCE_DIR}/fullchain.pem" ]]; then
  echo "Requesting Let's Encrypt certificate for ${IRCDOMAIN} via ${CHALLENGE_METHOD}"
  case "${CHALLENGE_METHOD}" in
    http-01)
      certbot certonly \
        --standalone \
        --preferred-challenges http \
        --agree-tos \
        --non-interactive \
        --email "${LETSENCRYPT_EMAIL}" \
        -d "${IRCDOMAIN}"
      ;;
    dns-01)
      : "${CERTBOT_DNS_PLUGIN:?Error: CERTBOT_DNS_PLUGIN must be set for dns-01 (e.g., cloudflare or digitalocean)}"
      PROPAGATION="${CERTBOT_DNS_PROPAGATION_SECONDS:-60}"
      ensure_dns_credentials_file() {
        local plugin="$1"
        # If an explicit credentials file is provided, use it
        if [[ -n "${CERTBOT_DNS_CREDENTIALS:-}" ]]; then
          echo "${CERTBOT_DNS_CREDENTIALS}"
          return 0
        fi
        local creds_path=""
        case "$plugin" in
          cloudflare)
            # Prefer uppercase env, fallback to lowercase for convenience
            local token="${DNS_CLOUDFLARE_API_TOKEN:-${dns_cloudflare_api_token:-}}"
            if [[ -z "$token" ]]; then
              echo "Error: Set DNS_CLOUDFLARE_API_TOKEN (or dns_cloudflare_api_token) or provide CERTBOT_DNS_CREDENTIALS for Cloudflare." >&2
              return 1
            fi
            creds_path="/run/certbot/cloudflare.ini"
            mkdir -p "$(dirname "$creds_path")"
            umask 077
            printf 'dns_cloudflare_api_token=%s\n' "$token" > "$creds_path"
            ;;
          digitalocean)
            local token="${DNS_DIGITALOCEAN_TOKEN:-${dns_digitalocean_token:-}}"
            if [[ -z "$token" ]]; then
              echo "Error: Set DNS_DIGITALOCEAN_TOKEN (or dns_digitalocean_token) or provide CERTBOT_DNS_CREDENTIALS for DigitalOcean." >&2
              return 1
            fi
            creds_path="/run/certbot/digitalocean.ini"
            mkdir -p "$(dirname "$creds_path")"
            umask 077
            printf 'dns_digitalocean_token=%s\n' "$token" > "$creds_path"
            ;;
          *)
            echo "Error: Unsupported CERTBOT_DNS_PLUGIN '$plugin'" >&2
            return 1
            ;;
        esac
        echo "$creds_path"
      }
      case "${CERTBOT_DNS_PLUGIN}" in
        cloudflare)
          CREDS_FILE="$(ensure_dns_credentials_file cloudflare)" || exit 1
          certbot certonly \
            --dns-cloudflare \
            --dns-cloudflare-credentials "${CREDS_FILE}" \
            --dns-cloudflare-propagation-seconds "${PROPAGATION}" \
            --agree-tos \
            --non-interactive \
            --email "${LETSENCRYPT_EMAIL}" \
            -d "${IRCDOMAIN}"
          ;;
        digitalocean)
          CREDS_FILE="$(ensure_dns_credentials_file digitalocean)" || exit 1
          certbot certonly \
            --dns-digitalocean \
            --dns-digitalocean-credentials "${CREDS_FILE}" \
            --dns-digitalocean-propagation-seconds "${PROPAGATION}" \
            --agree-tos \
            --non-interactive \
            --email "${LETSENCRYPT_EMAIL}" \
            -d "${IRCDOMAIN}"
          ;;
        *)
          echo "Error: Unsupported CERTBOT_DNS_PLUGIN='${CERTBOT_DNS_PLUGIN}'. Supported: cloudflare, digitalocean." >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "Error: Unsupported CERTBOT_CHALLENGE='${CHALLENGE_METHOD}'. Use http-01 or dns-01." >&2
      exit 1
      ;;
  esac
fi

cp "${CERT_SOURCE_DIR}/fullchain.pem" "${CERT_TARGET_DIR}/fullchain.pem"
cp "${CERT_SOURCE_DIR}/privkey.pem" "${CERT_TARGET_DIR}/privkey.pem"
chown -R ${UNREALIRCD_USER:-unreal}:${UNREALIRCD_USER:-unreal} "${CERT_TARGET_DIR}"
chmod 600 "${CERT_TARGET_DIR}/privkey.pem"

# Provide default certificate paths expected by UnrealIRCd
CONF_TLS_DIR="${UNREAL_ROOT}/conf/tls"
mkdir -p "${CONF_TLS_DIR}"
ln -sf "${CERT_TARGET_DIR}/fullchain.pem" "${CONF_TLS_DIR}/server.cert.pem"
ln -sf "${CERT_TARGET_DIR}/privkey.pem" "${CONF_TLS_DIR}/server.key.pem"
chown -R ${UNREALIRCD_USER:-unreal}:${UNREALIRCD_USER:-unreal} "${CONF_TLS_DIR}"

# Refresh certificate if close to expiry
certbot renew \
  --deploy-hook "cp ${CERT_SOURCE_DIR}/fullchain.pem ${CERT_TARGET_DIR}/fullchain.pem && cp ${CERT_SOURCE_DIR}/privkey.pem ${CERT_TARGET_DIR}/privkey.pem && chmod 600 ${CERT_TARGET_DIR}/privkey.pem && chown -R ${UNREALIRCD_USER:-unreal}:${UNREALIRCD_USER:-unreal} ${CERT_TARGET_DIR} && mkdir -p ${CONF_TLS_DIR} && ln -sf ${CERT_TARGET_DIR}/fullchain.pem ${CONF_TLS_DIR}/server.cert.pem && ln -sf ${CERT_TARGET_DIR}/privkey.pem ${CONF_TLS_DIR}/server.key.pem && chown -R ${UNREALIRCD_USER:-unreal}:${UNREALIRCD_USER:-unreal} ${CONF_TLS_DIR}" \
  --quiet || true

envsubst < "${CONFIG_TEMPLATE}" > "${TARGET_CONF}"
chown -R ${UNREALIRCD_USER:-unreal}:${UNREALIRCD_USER:-unreal} "${UNREAL_ROOT}"

exec gosu ${UNREALIRCD_USER:-unreal} "${UNREAL_ROOT}/bin/unrealircd" -F
