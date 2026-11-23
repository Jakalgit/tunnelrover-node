#!/bin/bash
# One Hysteria middle node per folder. The exit hop is VLESS XHTTP.
# listenPort and controlPort are required: another copy of this folder on the
# same host must use different ports. docker compose down stays inside this folder.
#
#   cp deploy/nodes.example.json deploy/nodes.json
#   sudo ./deploy.sh
#
# Safe to run again: templates are only read, generated files are rebuilt,
# traffic secrets stay in nodes.json, certbot runs only when a domain is missing.

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

python3 - "$NODES_FILE" "$SCRIPT_DIR" <<'PY' || exit 1
import json, pathlib, re, secrets, shlex, shutil, sys

nodes_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
generated = root / "generated"

with nodes_path.open(encoding="utf-8") as f:
    raw = json.load(f)

if isinstance(raw, list):
    if len(raw) != 1:
        raise SystemExit(
            "This folder installs one node. Copy the folder for the next node and give it other ports."
        )
    node = raw[0]
elif isinstance(raw, dict) and "nodes" in raw:
    raise SystemExit(
        "This folder installs one node. Copy the folder for the next node and give it other ports."
    )
elif isinstance(raw, dict):
    node = raw
else:
    raise SystemExit("deploy/nodes.json must be one node object")

def port_num(value, label):
    if value is None or value == "":
        raise SystemExit(f"Fill in deploy/nodes.json: {label}")
    try:
        number = int(value)
    except (TypeError, ValueError):
        raise SystemExit(f"{label} must be a port number")
    if not 1 <= number <= 65535:
        raise SystemExit(f"{label} must be between 1 and 65535")
    return number

def need(value, label):
    text = "" if value is None else str(value).strip()
    if not text or text.startswith("REPLACE_"):
        raise SystemExit(f"Fill in deploy/nodes.json: {label}")
    return text

name_re = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,40}$")
slug = re.sub(r"[^a-z0-9_-]+", "-", root.name.lower()).strip("-")
if not slug:
    raise SystemExit(f"Folder name {root.name!r} cannot be used as a compose project name")

if not isinstance(node, dict):
    raise SystemExit("deploy/nodes.json must be one node object")
name = need(node.get("name"), "name")
if not name_re.match(name):
    raise SystemExit("name must contain only letters, digits, '.', '_' or '-'")
domain = need(node.get("domain"), "domain")
token = need(node.get("nodeToken"), "nodeToken")
exit_cfg = node.get("exit") or {}
address = need(exit_cfg.get("address"), "exit.address")
exit_id = need(exit_cfg.get("id"), "exit.id")
exit_path = need(exit_cfg.get("path"), "exit.path")
if not exit_path.startswith("/"):
    raise SystemExit("exit.path must start with /")
exit_mode = str(exit_cfg.get("mode") or "packet-up")
listen_port = port_num(node.get("listenPort"), "listenPort")
control_port = port_num(node.get("controlPort"), "controlPort")
if listen_port == control_port or listen_port == 80 or control_port == 80:
    raise SystemExit("listenPort, controlPort and port 80 must be three different ports")
bind_http = node.get("bindHttp", True)
if isinstance(bind_http, str):
    bind_http = bind_http.strip().lower() not in ("0", "false", "no")
secrets_changed = False
secret = str(node.get("trafficStatsSecret") or "")
if not secret:
    secret = secrets.token_hex(32)
    node["trafficStatsSecret"] = secret
    secrets_changed = True
bandwidth = node.get("bandwidth") or {}
exit_port_value = exit_cfg.get("port")
if exit_port_value is None or exit_port_value == "":
    exit_port_value = 443
node_cfg = {
    "name": name,
    "domain": domain,
    "token": token,
    "listen_port": str(listen_port),
    "control_port": str(control_port),
    "bind_http": bind_http,
    "exit_address": address,
    "exit_port": str(port_num(exit_port_value, "exit.port")),
    "exit_id": exit_id,
    "exit_sni": str(exit_cfg.get("sni") or address),
    "exit_path": exit_path,
    "exit_mode": exit_mode,
    "secret": secret,
    "masquerade": str(node.get("masqueradeUrl") or "https://www.cloudflare.com"),
    "up": str(bandwidth.get("up") or "1 gbps"),
    "down": str(bandwidth.get("down") or "1 gbps"),
    "test_mode": "true" if node.get("testMode") else "false",
    "email": str(node.get("certbotEmail") or "info@tunnelrover.com"),
    "swap": str(node.get("swapSize") or "2G"),
}

if secrets_changed:
    with nodes_path.open("w", encoding="utf-8") as f:
        json.dump(raw, f, indent=2)
        f.write("\n")

if generated.exists():
    shutil.rmtree(generated)
(generated / "nginx").mkdir(parents=True)
(generated / "nodes").mkdir(parents=True)

def render(template, mapping, dest):
    text = (root / "templates" / template).read_text()
    for key, value in mapping.items():
        text = text.replace("{{" + key + "}}", value)
    if "{{" in text and "}}" in text:
        raise SystemExit(f"Unresolved placeholder left in {dest}")
    path = generated / dest
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if dest.endswith(".json"):
        json.loads(text)

node = node_cfg
mapping = {
    "DOMAIN": node["domain"],
    "LISTEN_PORT": node["listen_port"],
    "CONTROL_PORT": node["control_port"],
    "TRAFFIC_STATS_SECRET": node["secret"],
    "MASQUERADE_URL": node["masquerade"],
    "BANDWIDTH_UP": node["up"],
    "BANDWIDTH_DOWN": node["down"],
    "EXIT_ADDRESS": node["exit_address"],
    "EXIT_PORT": node["exit_port"],
    "EXIT_ID": node["exit_id"],
    "EXIT_SNI": node["exit_sni"],
    "EXIT_XHTTP_PATH": node["exit_path"],
    "EXIT_XHTTP_MODE": node["exit_mode"],
    "ROOT": str(root),
}
render("node-single.conf.template", mapping, f"nginx/{node['name']}.conf")
render("hysteria-server-config.yaml.template", mapping, f"nodes/{node['name']}/hysteria-server-config.yaml")
render("xray-exit-config.json.template", mapping, f"nodes/{node['name']}/xray-exit-config.json")
(generated / "nodes" / node["name"] / ".env").write_text(
    "\n".join([
        f"NODE_TOKEN={node['token']}",
        f"HYSTERIA_TRAFFIC_SECRET={node['secret']}",
        "REDIS_HOST=redis",
        "REDIS_PORT=6379",
        "HYSTERIA_HOST=hysteria",
        "HYSTERIA_TRAFFIC_PORT=9999",
        f"TEST_MODE={node['test_mode']}",
        "",
    ])
)

ports = [f'      - "{node["control_port"]}:{node["control_port"]}"']
if node["bind_http"]:
    ports.insert(0, '      - "80:80"')

lines = [
    "networks:",
    "  instance-network:",
    "",
    "services:",
    "  nginx:",
    "    image: nginx:alpine",
    f"    container_name: nginx-{slug}",
    "    restart: always",
    "    ports:",
    *ports,
    "    volumes:",
    f"      - {root}/nginx.conf:/etc/nginx/conf.d/default.conf:ro",
    f"      - {root}/generated/nginx:/etc/nginx/conf.d/nodes:ro",
    f"      - {root}/nginx-certs:/etc/nginx/certs:ro",
    f"      - {root}/index.html:/etc/nginx/html/index.html:ro",
    "    networks:",
    "      - instance-network",
    "",
    "  promtail:",
    "    image: grafana/promtail:latest",
    f"    container_name: promtail-{slug}",
    "    restart: unless-stopped",
    "    volumes:",
    "      - /var/lib/docker/containers:/var/lib/docker/containers:ro",
    "      - /var/run/docker.sock:/var/run/docker.sock",
    f"      - {root}/promtail-config.yaml:/etc/promtail/config.yml",
    "    command: -config.file=/etc/promtail/config.yml",
    "    privileged: true",
    "    networks:",
    "      - instance-network",
    "",
    "  redis:",
    "    image: redis:7-alpine",
    f"    container_name: redis-{slug}",
    "    restart: unless-stopped",
    '    command: redis-server --save "" --appendonly no',
    "    networks:",
    "      - instance-network",
    "",
    "  nest-app:",
    f"    container_name: nest-app-{slug}",
    "    restart: always",
    "    build:",
    f"      context: {root}",
    "      dockerfile: Dockerfile.nestjs",
    "    env_file:",
    f"      - {root}/generated/nodes/{node['name']}/.env",
    "    networks:",
    "      - instance-network",
    "    depends_on:",
    "      - redis",
    "",
    "  xray-exit:",
    "    image: teddysun/xray:latest",
    f"    container_name: xray-exit-{slug}",
    "    hostname: xray-exit",
    "    restart: unless-stopped",
    "    volumes:",
    f"      - {root}/generated/nodes/{node['name']}/xray-exit-config.json:/etc/xray/config.json:ro",
    "    command: xray run -config /etc/xray/config.json",
    "    networks:",
    "      - instance-network",
    "",
    "  hysteria:",
    "    image: tobyxdd/hysteria:latest",
    f"    container_name: hysteria-{slug}",
    "    restart: unless-stopped",
    "    ports:",
    f'      - "{node["listen_port"]}:{node["listen_port"]}/udp"',
    f'      - "{node["listen_port"]}:{node["listen_port"]}/tcp"',
    "    volumes:",
    f"      - {root}/generated/nodes/{node['name']}/hysteria-server-config.yaml:/etc/hysteria/config.yaml:ro",
    f"      - {root}/nginx-certs:/etc/hysteria/certs:ro",
    "    command: server -c /etc/hysteria/config.yaml",
    "    networks:",
    "      - instance-network",
    "    depends_on:",
    "      - nest-app",
    "      - xray-exit",
]

(generated / "docker-compose.yaml").write_text("\n".join(lines) + "\n")
(generated / "domains.txt").write_text(node["domain"] + "\n")
(generated / "summary.txt").write_text(
    f"{node['name']} {node['domain']} {node['listen_port']} {node['control_port']}\n"
)
(generated / "deploy.env").write_text(
    "\n".join([
        f"SWAP_SIZE={shlex.quote(node['swap'])}",
        f"CERTBOT_EMAIL={shlex.quote(node['email'])}",
        f"PROJECT_SLUG={shlex.quote(slug)}",
        "",
    ])
)

env_path = root / ".env"
existing = env_path.read_text(encoding="utf-8").splitlines() if env_path.exists() else []
updates = {
    "COMPOSE_FILE": "generated/docker-compose.yaml",
    "COMPOSE_PROJECT_NAME": slug,
}
written = []
seen = set()
for line in existing:
    key = line.split("=", 1)[0] if line and not line.startswith("#") and "=" in line else None
    if key in updates:
        written.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        written.append(line)
for key, value in updates.items():
    if key not in seen:
        written.append(f"{key}={value}")
env_path.write_text("\n".join(written).rstrip() + "\n")
print(f"Generated node {node['name']} in project {slug}")
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

compose up -d --build --remove-orphans

echo
echo "Done. Hysteria middle node (project $PROJECT_SLUG):"
read -r name domain listen control < "$GENERATED_DIR/summary.txt"
echo "  hysteria2://<USER_UUID>@$domain:$listen?sni=$domain"
echo "  https://$domain:$control  → nest-app control API"
echo
echo "Remove only this folder's containers and its built image:"
echo "  docker compose down --rmi local --volumes --remove-orphans"
