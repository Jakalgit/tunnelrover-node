#!/bin/bash
# Middle-node xhttp. One VPS, one nginx, N relay stacks.
#
#   cp deploy/nodes.example.json deploy/nodes.json
#   sudo ./deploy.sh
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
nodes_path = pathlib.Path(sys.argv[2])
if not nodes_path.is_absolute():
    nodes_path = root / nodes_path

with nodes_path.open(encoding="utf-8") as f:
    raw = json.load(f)

if isinstance(raw, dict) and isinstance(raw.get("nodes"), list):
    settings = raw
    nodes = raw["nodes"]
elif isinstance(raw, list):
    settings = raw[0] if raw else {}
    nodes = raw
elif isinstance(raw, dict) and raw.get("domain"):
    settings = raw
    nodes = [raw]
else:
    raise SystemExit("deploy/nodes.json must be a node array or {\"nodes\": [...]}")

if not nodes:
    raise SystemExit("No nodes defined in deploy/nodes.json")

name_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,62}$")
default_path = "/assets/build/_app/immutable/chunks/"
default_mode = "packet-up"

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
    name = need(node.get("name"), f"nodes[{index}].name")
    domain = need(node.get("domain"), f"{name}.domain")
    token = need(node.get("nodeToken"), f"{name}.nodeToken")
    if not name_re.match(name):
        raise SystemExit(f"Node name {name!r} must match {name_re.pattern}")
    exit_cfg = node.get("exit") or {}
    exit_address = need(exit_cfg.get("address"), f"{name}.exit.address")
    exit_id = need(exit_cfg.get("id"), f"{name}.exit.id")
    xhttp_path = str(node.get("xhttpPath") or default_path)
    xhttp_mode = str(node.get("xhttpMode") or default_mode)
    mapping = {
        "NODE_NAME": name,
        "DOMAIN": domain,
        "XHTTP_PATH": xhttp_path,
        "XHTTP_MODE": xhttp_mode,
        "EXIT_ADDRESS": exit_address,
        "EXIT_ID": exit_id,
        "EXIT_SNI": str(exit_cfg.get("sni") or exit_address),
        "EXIT_XHTTP_PATH": str(exit_cfg.get("xhttpPath") or xhttp_path),
        "EXIT_XHTTP_MODE": str(exit_cfg.get("xhttpMode") or xhttp_mode),
    }
    render("templates/node-single.conf.template", mapping, f"generated/nginx/nodes/{name}.conf")
    config = render("templates/xray-config.json.template", mapping, f"generated/nodes/{name}/xray-config.json")
    json.loads(config)
    test_mode = "true" if node.get("testMode") else "false"
    (generated / "nodes" / name / ".env").write_text(
        "\n".join([
            f"XRAY_HOST=xray-{name}",
            "XRAY_PORT=10085",
            f"NODE_TOKEN={token}",
            f"TEST_MODE={test_mode}",
            "",
        ])
    )
    rendered.append({"name": name, "domain": domain, "path": xhttp_path})

first = rendered[0]["name"]
email = str(settings.get("certbotEmail") or "info@tunnelrover.com")
swap = str(settings.get("swapSize") or "2G")

def q(value):
    return "'" + str(value).replace("'", "'\\''") + "'"

(generated / "deploy.env").write_text(
    "\n".join([
        f"CERTBOT_EMAIL={q(email)}",
        f"SWAP_SIZE={q(swap)}",
        f"STACK_NAME={q(first)}",
        "",
    ])
)
(generated / "domains.txt").write_text("".join(f"{node['domain']}\n" for node in rendered))
(generated / "summary.txt").write_text("".join(f"{node['domain']} {node['path']}\n" for node in rendered))

services = f"""version: "3.9"

networks:
  instance-network:
    name: instance-network

services:
  nginx:
    image: nginx:alpine
    container_name: nginx-proxy-{first}
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080"
    volumes:
      - {root}/nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - {root}/generated/nginx/nodes:/etc/nginx/conf.d/nodes:ro
      - {root}/nginx-certs:/etc/nginx/certs:ro
      - {root}/index.html:/etc/nginx/html/index.html:ro
    networks:
      - instance-network

  promtail:
    image: grafana/promtail:latest
    container_name: promtail-{first}
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

for node in rendered:
    name = node["name"]
    services += f"""
  xray-{name}:
    image: teddysun/xray
    container_name: xray-{name}
    restart: unless-stopped
    volumes:
      - {root}/generated/nodes/{name}/xray-config.json:/etc/xray/config.json:ro
    command: xray run -config /etc/xray/config.json
    networks:
      - instance-network

  nest-app-{name}:
    container_name: nest-app-{name}
    restart: always
    build:
      context: {root}
      dockerfile: Dockerfile.nestjs
    env_file:
      - {root}/generated/nodes/{name}/.env
    networks:
      - instance-network
    depends_on:
      - xray-{name}
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
  docker compose --project-directory "$SCRIPT_DIR" -f "$SCRIPT_DIR/$GENERATED_DIR/docker-compose.yaml" "$@"
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
issue_certs

for required in nginx.conf index.html promtail-config.yaml; do
  if [[ ! -f "$required" ]]; then
    echo "Missing $required" >&2
    exit 1
  fi
done

compose up -d --build

echo
echo "Done. Shared nginx routes by server_name:"
while read -r domain path; do
  echo "  https://$domain$path  → xray relay"
  echo "  https://$domain:8080  → nest-app control API"
done < "$GENERATED_DIR/summary.txt"
