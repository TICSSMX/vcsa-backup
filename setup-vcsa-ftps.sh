#!/usr/bin/env bash
# =============================================================================
# setup-vcsa-ftps.sh — Ubuntu 24.04 (Noble)
# FTPS (vsftpd) para Backups de VCSA (File-Based Backup) en PUERTO 21
# - Usuario dedicado + chroot
# - FTPS explícito (AUTH TLS) con cert autofirmado
# - PASV fijo (firewall-friendly)
# - PAM listo para /usr/sbin/nologin (añade a /etc/shells)
# - Auto-prueba con curl (--ftp-ssl) y timeouts
# =============================================================================
set -euo pipefail

# ----------------------- Parámetros ajustables -------------------------------
FTP_USER="${FTP_USER:-vcsa-backup}"
FTP_PASS="${FTP_PASS:-VCSAbackup2025!}"           # exporta FTP_PASS si quieres otra
FTP_HOME="${FTP_HOME:-/srv/ftp/${FTP_USER}}"
PASV_MIN="${PASV_MIN:-40000}"
PASV_MAX="${PASV_MAX:-40100}"
PASV_ADDR="${PASV_ADDR:-$(hostname -I | awk '{print $1}')}"   # IP/FQDN visible por VCSA
CERT_CN="${CERT_CN:-$PASV_ADDR}"                                 # CN del certificado

log(){ printf '[INFO] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Falta comando: $1"; }

# ----------------------------- Instalación -----------------------------------
[[ $EUID -eq 0 ]] || die "Ejecuta con sudo/root."
export DEBIAN_FRONTEND=noninteractive
log "Instalando paquetes..."
apt-get update -y >/dev/null
apt-get install -y vsftpd openssl ca-certificates curl coreutils >/dev/null
need vsftpd; need openssl; need curl; need timeout

# ----------------------------- Usuario/Permisos ------------------------------
if id -u "${FTP_USER}" >/dev/null 2>&1; then
  log "Usuario ${FTP_USER} ya existe; se reutiliza."
else
  log "Creando usuario ${FTP_USER} (shell nologin, chroot en ${FTP_HOME})..."
  adduser --home "${FTP_HOME}" --shell /usr/sbin/nologin --disabled-password --gecos "" "${FTP_USER}"
fi
echo "${FTP_USER}:${FTP_PASS}" | chpasswd

# PAM: asegura que /usr/sbin/nologin sea shell válida para pam_shells
grep -qx "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

# Directorios
mkdir -p "${FTP_HOME}/backups"
chown -R "${FTP_USER}:${FTP_USER}" "${FTP_HOME}"
chmod 750 "${FTP_HOME}" "${FTP_HOME}/backups"

# ----------------------------- Certificado TLS -------------------------------
mkdir -p /etc/vsftpd/certs
if [[ ! -f /etc/vsftpd/certs/vsftpd.pem ]]; then
  log "Generando certificado autofirmado (CN=${CERT_CN})..."
  openssl req -x509 -nodes -newkey rsa:4096 -days 825 \
    -keyout /etc/vsftpd/certs/vsftpd.key \
    -out /etc/vsftpd/certs/vsftpd.crt \
    -subj "/CN=${CERT_CN}" >/dev/null 2>&1
  cat /etc/vsftpd/certs/vsftpd.key /etc/vsftpd/certs/vsftpd.crt > /etc/vsftpd/certs/vsftpd.pem
  chmod 600 /etc/vsftpd/certs/vsftpd.*
fi

# ---------------------------- Configuración ----------------------------------
[[ -f /etc/vsftpd.conf ]] && cp -n /etc/vsftpd.conf "/etc/vsftpd.conf.bak.$(date +%s)"

cat > /etc/vsftpd.conf <<EOF
listen=YES
listen_ipv6=NO
listen_port=21

anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
check_shell=NO

chroot_local_user=YES
allow_writeable_chroot=YES

xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
xferlog_std_format=NO
log_ftp_protocol=YES
dual_log_enable=YES

idle_session_timeout=600
data_connection_timeout=120

pasv_enable=YES
pasv_min_port=${PASV_MIN}
pasv_max_port=${PASV_MAX}
pasv_address=${PASV_ADDR}

max_clients=50
max_per_ip=10

userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO

ssl_enable=YES
rsa_cert_file=/etc/vsftpd/certs/vsftpd.pem
rsa_private_key_file=/etc/vsftpd/certs/vsftpd.pem
force_local_logins_ssl=YES
force_local_data_ssl=YES
require_ssl_reuse=NO

pam_service_name=vsftpd
EOF

echo "${FTP_USER}" > /etc/vsftpd.userlist
chmod 600 /etc/vsftpd.userlist

# ------------------------------- Firewall ------------------------------------
if command -v ufw >/dev/null 2>&1; then
  ufw allow 21/tcp || true
  ufw allow ${PASV_MIN}:${PASV_MAX}/tcp || true
else
  warn "Asegura abrir 21/tcp y ${PASV_MIN}-${PASV_MAX}/tcp en tu firewall/NAT."
fi

# ------------------------------- Servicio ------------------------------------
systemctl enable vsftpd >/dev/null
systemctl restart vsftpd

# ------------------------------- Auto-prueba ---------------------------------
log "Auto-prueba FTPS (AUTH TLS) con curl..."
set +e
timeout 10s curl -sS -k --ftp-ssl --ssl-reqd --ftp-pasv \
  --list-only "ftp://${PASV_ADDR}/backups/" \
  --user "${FTP_USER}:${FTP_PASS}" >/dev/null 2>&1
RC_LIST=$?
echo "ok" >/tmp/.ftps-test.$$ || true
timeout 10s curl -sS -k --ftp-ssl --ssl-reqd --ftp-pasv \
  -T /tmp/.ftps-test.$$ "ftp://${PASV_ADDR}/backups/.ftps-test.$$" \
  --user "${FTP_USER}:${FTP_PASS}" >/dev/null 2>&1
RC_PUT=$?
timeout 10s curl -sS -k --ftp-ssl --ssl-reqd --ftp-pasv \
  -Q "-DELE backups/.ftps-test.$$" "ftp://${PASV_ADDR}/" \
  --user "${FTP_USER}:${FTP_PASS}" >/dev/null 2>&1
RC_DEL=$?
rm -f /tmp/.ftps-test.$$ || true
set -e

[[ $RC_LIST -eq 0 ]] || die "LIST falló (rc=$RC_LIST). Revisa puertos/ACL y /var/log/vsftpd.log."
[[ $RC_PUT  -eq 0 ]] || die "PUT falló (rc=$RC_PUT). Revisa permisos en ${FTP_HOME}/backups."
[[ $RC_DEL  -eq 0 ]] || die "DELETE falló (rc=$RC_DEL)."

# ------------------------------- Resumen -------------------------------------
echo
echo "================= FTPS listo y probado ================="
echo " Usuario........: ${FTP_USER}"
echo " Password.......: ${FTP_PASS}"
echo " Home...........: ${FTP_HOME}"
echo " Carpeta backup.: ${FTP_HOME}/backups"
echo " URL VCSA.......: ftps://${PASV_ADDR}/backups"
echo " Puertos........: 21/tcp + ${PASV_MIN}-${PASV_MAX}/tcp (pasivo)"
echo " Certificado....: CN=${CERT_CN} (autofirmado)"
echo " Logs...........: /var/log/vsftpd.log"
echo " Nota VAMI......: la ruta es RELATIVA al HOME del usuario (/backups)."
echo "========================================================"
