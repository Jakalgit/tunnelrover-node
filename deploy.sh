#!/bin/bash
# Several Hysteria middle nodes on one VPS.
# Each node has its own listenPort (client UDP+TCP) and controlPort (nest API).
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
    nodes = raw
elif isinstance(raw, dict) and isinstance(raw.get("nodes"), list):
    nodes = raw["nodes"]
elif isinstance(raw, dict):
    nodes = [raw]
else:
    raise SystemExit("deploy/nodes.json must be an array of nodes")

if not nodes:
    raise SystemExit("deploy/nodes.json has no nodes")

def port_num(value, default, label):
    if value is None or value == "":
        value = default
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
used_ports = {80: "certbot on port 80"}
seen_names = set()
seen_domains = set()
secrets_changed = False
prepared = []

for index, node in enumerate(nodes):
    if not isinstance(node, dict):
        raise SystemExit(f"nodes[{index}] must be an object")
    label = f"nodes[{index}]"
    name = need(node.get("name"), f"{label}.name")
    if not name_re.match(name):
        raise SystemExit(f"{label}.name must contain only letters, digits, '.', '_' or '-'")
    if name in seen_names:
        raise SystemExit(f"Duplicate node name: {name}")
    seen_names.add(name)
    domain = need(node.get("domain"), f"{name}.domain")
    if domain in seen_domains:
        raise SystemExit(f"Duplicate domain: {domain}")
    seen_domains.add(domain)
    token = need(node.get("nodeToken"), f"{name}.nodeToken")
    exit_cfg = node.get("exit") or {}
    address = need(exit_cfg.get("address"), f"{name}.exit.address")
    auth = need(exit_cfg.get("auth"), f"{name}.exit.auth")
    listen_port = port_num(node.get("listenPort"), 443, f"{name}.listenPort")
    control_port = port_num(node.get("controlPort"), 8080, f"{name}.controlPort")
    for field, number in (("listenPort", listen_port), ("controlPort", control_port)):
        owner = used_ports.get(number)
        if owner:
            raise SystemExit(f"{name} {field} {number} overlaps {owner}")
        used_ports[number] = f"{name} {field}"
    secret = str(node.get("trafficStatsSecret") or "")
    if not secret:
        secret = secrets.token_hex(32)
        node["trafficStatsSecret"] = secret
        secrets_changed = True
    bandwidth = node.get("bandwidth") or {}
    prepared.append({
        "name": name,
        "domain": domain,
        "token": token,
        "listen_port": str(listen_port),
        "control_port": str(control_port),
        "exit_address": address,
        "exit_port": str(port_num(exit_cfg.get("port"), 443, f"{name}.exit.port")),
        "exit_auth": auth,
        "exit_sni": str(exit_cfg.get("sni") or address),
        "secret": secret,
        "masquerade": str(node.get("masqueradeUrl") or "https://www.cloudflare.com"),
        "up": str(bandwidth.get("up") or "1 gbps"),
        "down": str(bandwidth.get("down") or "1 gbps"),
        "test_mode": "true" if node.get("testMode") else "false",
        "email": str(node.get("certbotEmail") or "info@tunnelrover.com"),
        "swap": str(node.get("swapSize") or "2G"),
    })

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

lines = [
    "networks:",
    "  instance-network:",
    "    name: instance-network",
    "",
    "services:",
    "  nginx:",
    "    image: nginx:alpine",
    "    container_name: nginx-proxy",
    "    restart: always",
    "    ports:",
    '      - "80:80"',
]
for node in prepared:
    lines.append(f'      - "{node["control_port"]}:{node["control_port"]}"')
lines += [
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
    "    container_name: promtail",
    "    restart: unless-stopped",
    "    volumes:",
    "      - /var/lib/docker/containers:/var/lib/docker/containers:ro",
    "      - /var/run/docker.sock:/var/run/docker.sock",
    f"      - {root}/promtail-config.yaml:/etc/promtail/config.yml",
    "    command: -config.file=/etc/promtail/config.yml",
    "    privileged: true",
    "    networks:",
    "      - instance-network",
]

for node in prepared:
    name = node["name"]
    mapping = {
        "NODE_NAME": name,
        "DOMAIN": node["domain"],
        "LISTEN_PORT": node["listen_port"],
        "CONTROL_PORT": node["control_port"],
        "TRAFFIC_STATS_SECRET": node["secret"],
        "MASQUERADE_URL": node["masquerade"],
        "BANDWIDTH_UP": node["up"],
        "BANDWIDTH_DOWN": node["down"],
        "EXIT_ADDRESS": node["exit_address"],
        "EXIT_PORT": node["exit_port"],
        "EXIT_AUTH": node["exit_auth"],
        "EXIT_SNI": node["exit_sni"],
        "ROOT": str(root),
    }
    render("node-single.conf.template", mapping, f"nginx/{name}.conf")
    render("hysteria-server-config.yaml.template", mapping, f"nodes/{name}/hysteria-server-config.yaml")
    render("hysteria-exit-client.yaml.template", mapping, f"nodes/{name}/hysteria-exit-client.yaml")
    (generated / "nodes" / name / ".env").write_text(
        "\n".join([
            f"NODE_TOKEN={node['token']}",
            f"HYSTERIA_TRAFFIC_SECRET={node['secret']}",
            f"REDIS_HOST=redis-{name}",
            "REDIS_PORT=6379",
            f"HYSTERIA_HOST=hysteria-{name}",
            "HYSTERIA_TRAFFIC_PORT=9999",
            f"TEST_MODE={node['test_mode']}",
            "",
        ])
    )
    lines += [
        "",
        f"  redis-{name}:",
        "    image: redis:7-alpine",
        f"    container_name: redis-{name}",
        "    restart: unless-stopped",
        '    command: redis-server --save "" --appendonly no',
        "    networks:",
        "      - instance-network",
        "",
        f"  nest-app-{name}:",
        f"    container_name: nest-app-{name}",
        "    restart: always",
        "    image: node-nest-app",
        "    build:",
        f"      context: {root}",
        "      dockerfile: Dockerfile.nestjs",
        "    env_file:",
        f"      - {root}/generated/nodes/{name}/.env",
        "    networks:",
        "      - instance-network",
        "    depends_on:",
        f"      - redis-{name}",
        "",
        f"  hysteria-exit-{name}:",
        "    image: tobyxdd/hysteria:latest",
        f"    container_name: hysteria-exit-{name}",
        f"    hostname: hysteria-exit-{name}",
        "    restart: unless-stopped",
        "    volumes:",
        f"      - {root}/generated/nodes/{name}/hysteria-exit-client.yaml:/etc/hysteria/config.yaml:ro",
        "    command: client -c /etc/hysteria/config.yaml",
        "    networks:",
        "      instance-network:",
        "        aliases:",
        f"          - hysteria-exit-{name}",
        "",
        f"  hysteria-{name}:",
        "    image: tobyxdd/hysteria:latest",
        f"    container_name: hysteria-{name}",
        "    restart: unless-stopped",
        "    ports:",
        f'      - "{node["listen_port"]}:{node["listen_port"]}/udp"',
        f'      - "{node["listen_port"]}:{node["listen_port"]}/tcp"',
        "    volumes:",
        f"      - {root}/generated/nodes/{name}/hysteria-server-config.yaml:/etc/hysteria/config.yaml:ro",
        f"      - {root}/nginx-certs:/etc/hysteria/certs:ro",
        "    command: server -c /etc/hysteria/config.yaml",
        "    networks:",
        "      - instance-network",
        "    depends_on:",
        f"      - nest-app-{name}",
        f"      - hysteria-exit-{name}",
    ]

(generated / "docker-compose.yaml").write_text("\n".join(lines) + "\n")
(generated / "domains.txt").write_text("".join(f"{node['domain']}\n" for node in prepared))
(generated / "summary.txt").write_text(
    "".join(
        f"{node['name']} {node['domain']} {node['listen_port']} {node['control_port']}\n"
        for node in prepared
    )
)
(generated / "deploy.env").write_text(
    "\n".join([
        f"SWAP_SIZE={shlex.quote(prepared[0]['swap'])}",
        f"CERTBOT_EMAIL={shlex.quote(prepared[0]['email'])}",
        "",
    ])
)
print(f"Generated {len(prepared)} hysteria middle node(s)")
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

compose up -d --build --remove-orphans

echo
echo "Done. Hysteria middle nodes:"
while read -r name domain listen control; do
  echo "  $name"
  echo "    hysteria2://<USER_UUID>@$domain:$listen?sni=$domain"
  echo "    https://$domain:$control  → nest-app control API"
done < "$GENERATED_DIR/summary.txt"
