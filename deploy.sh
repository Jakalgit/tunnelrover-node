#!/bin/bash
# One XDNS exit node per host. Clients reach it through DNS, and it opens the internet itself.
# UDP 53 can belong to only one folder on the machine.
#
#   cp deploy/nodes.example.json deploy/nodes.json
#   sudo ./deploy.sh
#   sudo ./deploy.sh down
#
# Safe to run again: templates are only read, generated files are rebuilt,
# certbot runs only when a domain is missing from the live certificate.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

NODES_FILE="${NODES_FILE:-deploy/nodes.json}"
GENERATED_DIR="generated"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo ./deploy.sh" >&2
  exit 1
fi

folder_slug() {
  python3 - "$SCRIPT_DIR" <<'PY'
import pathlib, re, sys
slug = re.sub(r"[^a-z0-9_-]+", "-", pathlib.Path(sys.argv[1]).name.lower()).strip("-")
if not slug:
    raise SystemExit("Folder name cannot be used as a compose project name")
print(slug)
PY
}

if [[ "${1:-}" == "down" ]]; then
  PROJECT_SLUG="$(folder_slug)"
  if [[ -f "$GENERATED_DIR/docker-compose.yaml" ]]; then
    docker compose \
      --project-name "$PROJECT_SLUG" \
      --project-directory "$SCRIPT_DIR" \
      -f "$SCRIPT_DIR/$GENERATED_DIR/docker-compose.yaml" \
      down --rmi local --volumes --remove-orphans
  fi
  echo "Removed project ${PROJECT_SLUG} and its containers."
  exit 0
fi

if [[ -n "${1:-}" ]]; then
  echo "Usage: sudo ./deploy.sh [down]" >&2
  exit 1
fi

if [[ ! -f "$NODES_FILE" ]]; then
  if [[ -f deploy/nodes.example.json ]]; then
    cp deploy/nodes.example.json "$NODES_FILE"
    echo "Created $NODES_FILE from example. Fill it and run again." >&2
    exit 1
  fi
  echo "Missing $NODES_FILE" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y python3
fi

python3 - "$SCRIPT_DIR" "$NODES_FILE" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1]).resolve()
slug = re.sub(r"[^a-z0-9_-]+", "-", root.name.lower()).strip("-")
if not slug:
    raise SystemExit(f"Folder name {root.name!r} cannot be used as a compose project name")
nodes_path = pathlib.Path(sys.argv[2])
if not nodes_path.is_absolute():
    nodes_path = root / nodes_path

with nodes_path.open(encoding="utf-8") as f:
    raw = json.load(f)

if isinstance(raw, list):
    if len(raw) != 1:
        raise SystemExit("This host installs one XDNS node: UDP 53 cannot be shared.")
    node = raw[0]
elif isinstance(raw, dict) and raw.get("domain"):
    node = raw
else:
    raise SystemExit("deploy/nodes.json must be one node object")

nodes = [node]

name_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
domain_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$")

def need(value, label):
    if not value or str(value).startswith("REPLACE_"):
        raise SystemExit(f"Fill in deploy/nodes.json: {label}")
    return str(value)

def render(template, mapping, dest):
    text = (root / template).read_text()
    for key, value in mapping.items():
        text = text.replace("{{" + key + "}}", value)
    if "{{" in text and "}}" in text:
        raise SystemExit(f"Unresolved placeholder left in {dest}")
    path = root / dest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    return text

generated = root / "generated"
if generated.exists():
    import shutil
    shutil.rmtree(generated)
(generated / "nginx" / "nodes").mkdir(parents=True)
(generated / "nodes").mkdir(parents=True)

rendered = []
for index, node in enumerate(nodes):
    if not isinstance(node, dict):
        raise SystemExit(f"Node #{index} must be an object")
    name = need(node.get("name"), "name")
    domain = need(node.get("domain"), "domain")
    tunnel = need(node.get("tunnelDomain"), "tunnelDomain")
    token = need(node.get("nodeToken"), "nodeToken")
    if not name_re.match(name):
        raise SystemExit(f"Node name {name!r} must match {name_re.pattern}")
    if not domain_re.match(tunnel) or tunnel.count(".") < 1:
        raise SystemExit("tunnelDomain must be a DNS name, for example t.example.com")
    try:
        control_port = int(node.get("controlPort"))
    except (TypeError, ValueError):
        raise SystemExit("Fill in deploy/nodes.json: controlPort")
    if control_port in (53, 80) or not 1 <= control_port <= 65535:
        raise SystemExit("controlPort must be a free TCP port other than 53 and 80")
    mapping = {
        "NODE_NAME": name,
        "DOMAIN": domain,
        "TUNNEL_DOMAIN": tunnel,
        "CONTROL_PORT": str(control_port),
    }
    render("templates/node-single.conf.template", mapping, f"generated/nginx/nodes/{name}.conf")
    config = render("templates/xray-config.json.template", mapping, f"generated/nodes/{name}/xray-config.json")
    json.loads(config)
    test_mode = "true" if node.get("testMode") else "false"
    (generated / "nodes" / name / ".env").write_text(
        "\n".join([
            "XRAY_HOST=xray",
            "XRAY_PORT=10085",
            "XRAY_INBOUND_TAG=vless-xdns",
            f"NODE_TOKEN={token}",
            f"TEST_MODE={test_mode}",
            "",
        ])
    )
    rendered.append({
        "name": name,
        "domain": domain,
        "tunnel": tunnel,
        "control": control_port,
    })

node = rendered[0]
email = str(nodes[0].get("certbotEmail") or "info@tunnelrover.com")
swap = str(nodes[0].get("swapSize") or "2G")

def q(value):
    return "'" + str(value).replace("'", "'\\''") + "'"

(generated / "deploy.env").write_text(
    "\n".join([
        f"CERTBOT_EMAIL={q(email)}",
        f"SWAP_SIZE={q(swap)}",
        f"PROJECT_SLUG={q(slug)}",
        f"CONTROL_PORT={q(node['control'])}",
        "",
    ])
)
(generated / "domains.txt").write_text(node["domain"] + "\n")
(generated / "summary.txt").write_text(
    f"{node['domain']} {node['tunnel']} {node['control']}\n"
)

services = f"""networks:
  instance-network:

services:
  nginx:
    image: nginx:alpine
    container_name: nginx-{slug}
    restart: always
    ports:
      - "80:80"
      - "{node['control']}:{node['control']}"
    volumes:
      - {root}/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - {root}/generated/nginx/nodes:/etc/nginx/conf.d/nodes:ro
      - {root}/nginx-certs:/etc/nginx/certs:ro
      - {root}/index.html:/etc/nginx/html/index.html:ro
    networks:
      - instance-network

  promtail:
    image: grafana/promtail:latest
    container_name: promtail-{slug}
    restart: unless-stopped
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - {root}/promtail-config.yaml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
    privileged: true
    networks:
      - instance-network
"""

name = node["name"]
services += f"""
  xray:
    image: teddysun/xray:latest
    container_name: xray-{slug}
    restart: unless-stopped
    ports:
      - "53:53/udp"
    volumes:
      - {root}/generated/nodes/{name}/xray-config.json:/etc/xray/config.json:ro
    command: xray run -config /etc/xray/config.json
    networks:
      - instance-network

  nest-app:
    container_name: nest-app-{slug}
    restart: always
    build:
      context: {root}
      dockerfile: Dockerfile.nestjs
    env_file:
      - {root}/generated/nodes/{name}/.env
    networks:
      - instance-network
    depends_on:
      - xray
"""

(generated / "docker-compose.yaml").write_text(services)
print(f"Generated {len(rendered)} node(s)")
PY

# shellcheck disable=SC1091
source "$GENERATED_DIR/deploy.env"
mapfile -t CERT_DOMAINS < "$GENERATED_DIR/domains.txt"

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable sh
  fi
  systemctl enable --now docker

  if ! command -v certbot >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y certbot openssl iptables-persistent nano
  fi

  if ! docker compose version >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y docker-compose-plugin
  fi
}

ensure_swap() {
  if [[ -f /swapfile ]]; then
    return
  fi
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
}

compose() {
  docker compose \
    --project-name "$PROJECT_SLUG" \
    --project-directory "$SCRIPT_DIR" \
    -f "$SCRIPT_DIR/$GENERATED_DIR/docker-compose.yaml" \
    "$@"
}

ensure_dns_port() {
  if command -v ss >/dev/null 2>&1 && ss -lunH 'sport = :53' | grep -q .; then
    echo "UDP 53 is already in use. XDNS must bind it itself; free the port and run again." >&2
    ss -lunp 'sport = :53' >&2 || true
    exit 1
  fi
}

domain_in_cert() {
  local text="$1"
  local domain="$2"
  local escaped
  escaped="$(printf '%s' "$domain" | sed 's/[.[\*^$()+?{|]/\\&/g')"
  grep -qE "DNS:${escaped}(,|$)" <<<"$text"
}

cert_covers() {
  local cert="$1"
  local text domain
  [[ -f "$cert" ]] || return 1
  text="$(openssl x509 -in "$cert" -noout -ext subjectAltName 2>/dev/null || true)"
  for domain in "${CERT_DOMAINS[@]}"; do
    domain_in_cert "$text" "$domain" || return 1
  done
}

find_covering_cert() {
  local dir
  [[ -d /etc/letsencrypt/live ]] || return 1
  for dir in /etc/letsencrypt/live/*/; do
    if cert_covers "${dir}fullchain.pem"; then
      printf '%s' "${dir%/}"
      return 0
    fi
  done
  return 1
}

find_partial_cert() {
  local dir domain text
  [[ -d /etc/letsencrypt/live ]] || return 1
  for dir in /etc/letsencrypt/live/*/; do
    [[ -f "${dir}fullchain.pem" ]] || continue
    text="$(openssl x509 -in "${dir}fullchain.pem" -noout -ext subjectAltName 2>/dev/null || true)"
    for domain in "${CERT_DOMAINS[@]}"; do
      if domain_in_cert "$text" "$domain"; then
        printf '%s' "${dir%/}"
        return 0
      fi
    done
  done
  return 1
}

issue_certs() {
  local live_dir="" partial="" domain
  local -a certbot_args
  if live_dir="$(find_covering_cert)"; then
    :
  else
    compose down || true
    certbot_args=(certonly --standalone)
    if partial="$(find_partial_cert)"; then
      certbot_args+=(--cert-name "$(basename "$partial")" --expand)
    fi
    for domain in "${CERT_DOMAINS[@]}"; do
      certbot_args+=(-d "$domain")
    done
    certbot "${certbot_args[@]}" \
      --non-interactive \
      --agree-tos \
      --email "$CERTBOT_EMAIL" \
      --no-eff-email
    live_dir="$(find_covering_cert || true)"
  fi

  if [[ -z "$live_dir" || ! -f "${live_dir}/fullchain.pem" ]]; then
    echo "Certificate was not issued for: ${CERT_DOMAINS[*]}" >&2
    exit 1
  fi

  mkdir -p ./nginx-certs
  cp "${live_dir}/fullchain.pem" ./nginx-certs/fullchain.pem
  cp "${live_dir}/privkey.pem" ./nginx-certs/privkey.pem
  chmod 644 ./nginx-certs/*.pem
}

install_docker
ensure_swap
ensure_dns_port
issue_certs

for required in nginx.conf index.html promtail-config.yaml; do
  if [[ ! -f "$required" ]]; then
    echo "Missing $required" >&2
    exit 1
  fi
done

compose up -d --build

echo
echo "Done. XDNS exit node (project $PROJECT_SLUG):"
read -r domain tunnel control < "$GENERATED_DIR/summary.txt"
echo "  DNS tunnel name: $tunnel"
echo "  Point its NS record at an A record of this server. UDP 53 is Xray."
echo "  https://$domain:$control  → nest-app control API"
echo
echo "Remove only this folder:"
echo "  sudo ./deploy.sh down"
