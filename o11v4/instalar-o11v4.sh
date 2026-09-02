#!/usr/bin/env bash
set -Eeuo pipefail
ZIP_URL="https://raw.githubusercontent.com/cs-plus/o11/25e6d385caf5c062f9c33a4aad49a64865c26aeb/o11v4/o11v4.zip"
INSTALL_DIR="/home/o11v4"
SERVICE_FILE="/etc/systemd/system/o11v4run.service"
LICENSE_PORT_DEFAULT="180"
O11_PORT_DEFAULT="8484"

ok()    { printf '\n\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn()  { printf '\n\033[1;33m[AVISO]\033[0m %s\n' "$*"; }
error() { printf '\n\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2; exit 1; }
trap 'error "Falha na linha $LINENO. Verifique a mensagem exibida acima."' ERR

valid_ipv4() {
  local ip=$1 octet
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    (( 10#$octet >= 0 && 10#$octet <= 255 )) || return 1
  done
}

detect_ip() {
  local detected=""
  if command -v curl >/dev/null 2>&1; then
    detected=$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)
  fi
  if ! valid_ipv4 "$detected"; then
    detected=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  fi
  valid_ipv4 "$detected" && printf '%s' "$detected"
}

[[ $EUID -eq 0 ]] || error "Execute como root: sudo ./instalar-o11v4.sh"

printf '=== Instalador automático do O11v4 ===\n'
read -r -s -p "Senha do arquivo o11v4.zip: " ZIP_PASSWORD
printf '\n'
[[ -n "$ZIP_PASSWORD" ]] || error "A senha não pode ficar vazia."

DETECTED_IP=$(detect_ip || true)
if [[ -n "$DETECTED_IP" ]]; then
  read -r -p "IP deste servidor [$DETECTED_IP]: " SERVER_IP
  SERVER_IP=${SERVER_IP:-$DETECTED_IP}
else
  read -r -p "IP deste servidor: " SERVER_IP
fi
valid_ipv4 "$SERVER_IP" || error "IP inválido: $SERVER_IP"

read -r -p "Porta HTTP da licença [$LICENSE_PORT_DEFAULT]: " LICENSE_PORT
LICENSE_PORT=${LICENSE_PORT:-$LICENSE_PORT_DEFAULT}
[[ "$LICENSE_PORT" =~ ^[0-9]+$ ]] && (( LICENSE_PORT >= 1 && LICENSE_PORT <= 65535 )) \
  || error "Porta inválida: $LICENSE_PORT"

read -r -p "Porta do O11 [$O11_PORT_DEFAULT]: " O11_PORT
O11_PORT=${O11_PORT:-$O11_PORT_DEFAULT}
[[ "$O11_PORT" =~ ^[0-9]+$ ]] && (( O11_PORT >= 1 && O11_PORT <= 65535 )) \
  || error "Porta inválida para o O11: $O11_PORT"
if [[ "$O11_PORT" == "$LICENSE_PORT" || "$O11_PORT" == "5454" || "$O11_PORT" == "443" ]]; then
  error "A porta $O11_PORT já é utilizada pelo servidor de licença. Escolha outra para o O11."
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y unzip curl ca-certificates

WORK_DIR=$(mktemp -d /tmp/o11v4-install.XXXXXX)
cleanup() { ZIP_PASSWORD=""; rm -rf -- "$WORK_DIR"; }
trap cleanup EXIT
ZIP_FILE="$WORK_DIR/o11v4.zip"
EXTRACT_DIR="$WORK_DIR/extraido"
mkdir -p "$EXTRACT_DIR"

ok "Baixando o11v4.zip..."
curl -fL --retry 3 --connect-timeout 15 -o "$ZIP_FILE" "$ZIP_URL"
[[ -s "$ZIP_FILE" ]] || error "O download gerou um arquivo vazio."
unzip -Z1 "$ZIP_FILE" >/dev/null 2>&1 || error "O download não contém um ZIP válido."
if ! unzip -P "$ZIP_PASSWORD" -tqq "$ZIP_FILE" >/dev/null 2>&1; then
  ZIP_PASSWORD=""
  error "Senha incorreta ou arquivo ZIP danificado."
fi
unzip -P "$ZIP_PASSWORD" -q "$ZIP_FILE" -d "$EXTRACT_DIR"
ZIP_PASSWORD=""

SOURCE_DIR="$EXTRACT_DIR"
if [[ ! -f "$SOURCE_DIR/server.js" || ! -f "$SOURCE_DIR/run.sh" ]]; then
  mapfile -t SERVER_FILES < <(find "$EXTRACT_DIR" -type f -name server.js -print)
  (( ${#SERVER_FILES[@]} == 1 )) || error "Não foi possível determinar a pasta extraída do O11v4."
  SOURCE_DIR=$(dirname "${SERVER_FILES[0]}")
fi
[[ -f "$SOURCE_DIR/server.js" ]] || error "server.js não encontrado no ZIP."
[[ -f "$SOURCE_DIR/run.sh" ]] || error "run.sh não encontrado no ZIP."
[[ -f "$SOURCE_DIR/o11v4" ]] || error "Executável o11v4 não encontrado no ZIP."

systemctl stop o11v4run.service 2>/dev/null || true
systemctl disable --now o11v4-license.service 2>/dev/null || true
rm -f /etc/systemd/system/o11v4-license.service
if command -v pm2 >/dev/null 2>&1; then
  pm2 delete licserver >/dev/null 2>&1 || true
fi

if [[ -d "$INSTALL_DIR" ]] && find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  BACKUP_DIR="${INSTALL_DIR}.backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "$INSTALL_DIR" "$BACKUP_DIR"
  warn "Instalação anterior copiada para $BACKUP_DIR"
fi

mkdir -p "$INSTALL_DIR"
cp -a "$SOURCE_DIR"/. "$INSTALL_DIR"/
chown -R root:root "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/run.sh" "$INSTALL_DIR/o11v4"

# Altera o parâmetro -p do executável no run.sh (padrão original: 8484).
sed -E -i \
  "s|(exec[[:space:]]+/home/o11v4/o11v4[[:space:]]+-p[[:space:]]+)[0-9]+|\\1$O11_PORT|" \
  "$INSTALL_DIR/run.sh"
grep -Eq "exec[[:space:]]+/home/o11v4/o11v4[[:space:]]+-p[[:space:]]+$O11_PORT([[:space:]]|$)" "$INSTALL_DIR/run.sh" \
  || error "Não consegui alterar a porta do O11 no run.sh."

if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt-get install -y nodejs
fi
node -v
npm -v

cd "$INSTALL_DIR"
npm install -g pm2
npm install express

sed -E -i \
  -e "s|^([[:space:]]*const[[:space:]]+ipAddress[[:space:]]*=[[:space:]]*)['\"][^'\"]*['\"]([[:space:]]*;.*)$|\\1'$SERVER_IP'\\2|" \
  -e "s|^([[:space:]]*const[[:space:]]+portHttp[[:space:]]*=[[:space:]]*)[0-9]+([[:space:]]*;.*)$|\\1$LICENSE_PORT\\2|" \
  -e "s|\[80,[[:space:]]*5454\]|[$LICENSE_PORT, 5454]|g" \
  "$INSTALL_DIR/server.js"

grep -Eq "const[[:space:]]+ipAddress[[:space:]]*=[[:space:]]*['\"]$SERVER_IP['\"]" "$INSTALL_DIR/server.js" \
  || error "Não consegui alterar ipAddress no server.js."
grep -Eq "const[[:space:]]+portHttp[[:space:]]*=[[:space:]]*$LICENSE_PORT" "$INSTALL_DIR/server.js" \
  || error "Não consegui alterar portHttp no server.js."

pm2 delete licserver >/dev/null 2>&1 || true
pm2 start "$INSTALL_DIR/server.js" --name licserver --silent
pm2 startup systemd -u root --hp /root >/dev/null
pm2 save --force

# O systemd substitui o nohup para não abrir duas instâncias do run.sh.
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=O11v4 Run Script Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/home/o11v4/run.sh
WorkingDirectory=/home/o11v4/
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable o11v4run.service
systemctl restart o11v4run.service
sleep 3

pm2 describe licserver >/dev/null 2>&1 || error "O licserver não foi registrado no PM2."
systemctl is-active --quiet o11v4run.service || {
  journalctl -u o11v4run.service -n 40 --no-pager
  error "o11v4run.service não iniciou."
}

ok "Instalação concluída conforme o tutorial."
printf 'IP configurado: %s\n' "$SERVER_IP"
printf 'Porta HTTP da licença: %s\n' "$LICENSE_PORT"
printf 'Porta do O11: %s\n' "$O11_PORT"
printf '\nVerificação:\n'
printf '  pm2 status licserver\n'
printf '  systemctl status o11v4run.service --no-pager\n'
