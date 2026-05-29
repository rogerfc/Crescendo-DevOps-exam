#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

MAGNOLIA_VERSION="6.2.74"
MAGNOLIA_BUNDLE="magnolia-community-demo-webapp-${MAGNOLIA_VERSION}-tomcat-bundle"
MAGNOLIA_URL="https://nexus.magnolia-cms.com/repository/public/info/magnolia/bundle/magnolia-community-demo-webapp/${MAGNOLIA_VERSION}/${MAGNOLIA_BUNDLE}.zip"
INSTALL_DIR="/opt/magnolia"

echo "==> Updating system packages"
dnf update -y

echo "==> Installing dependencies"
dnf install -y java-11-amazon-corretto nginx unzip

echo "==> Creating magnolia system user"
useradd -r -s /sbin/nologin -d "${INSTALL_DIR}" magnolia

echo "==> Downloading Magnolia bundle"
curl -fsSL -o "/tmp/${MAGNOLIA_BUNDLE}.zip" "${MAGNOLIA_URL}"

echo "==> Extracting bundle to ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
unzip -q "/tmp/${MAGNOLIA_BUNDLE}.zip" -d "${INSTALL_DIR}"
rm "/tmp/${MAGNOLIA_BUNDLE}.zip"

echo "==> Discovering Tomcat directory"
CATALINA_HOME=$(find "${INSTALL_DIR}" -maxdepth 2 -type d -name 'apache-tomcat-*' | head -1)
if [[ -z "${CATALINA_HOME}" ]]; then
  echo "ERROR: Could not find Tomcat directory under ${INSTALL_DIR}" >&2
  exit 1
fi
echo "Tomcat found at: ${CATALINA_HOME}"

echo "==> Setting permissions"
chown -R magnolia:magnolia "${INSTALL_DIR}"
chmod +x "${CATALINA_HOME}"/bin/*.sh

echo "==> Creating systemd service"
cat > /etc/systemd/system/magnolia.service << EOF
[Unit]
Description=Magnolia CMS
After=network.target

[Service]
Type=simple
User=magnolia
Group=magnolia
Environment=JAVA_HOME=/usr/lib/jvm/java-11-amazon-corretto
Environment=CATALINA_HOME=${CATALINA_HOME}
Environment=JAVA_OPTS="-Xms512m -Xmx1g -Djava.awt.headless=true"
ExecStart=${CATALINA_HOME}/bin/catalina.sh run
ExecStop=${CATALINA_HOME}/bin/catalina.sh stop
Restart=on-failure
RestartSec=15
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now magnolia

echo "==> Configuring Nginx"
# Remove default vhost so it doesn't conflict
rm -f /etc/nginx/conf.d/default.conf

cat > /etc/nginx/conf.d/magnolia.conf << 'EOF'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass            http://localhost:8080;
        proxy_set_header      Host              $host;
        proxy_set_header      X-Real-IP         $remote_addr;
        proxy_set_header      X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto $scheme;
        proxy_read_timeout    300s;
        proxy_connect_timeout 10s;
    }
}
EOF

systemctl enable --now nginx

echo "==> Configuring logrotate for Tomcat logs"
cat > /etc/logrotate.d/magnolia << EOF
${CATALINA_HOME}/logs/*.* {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
EOF

echo "==> Bootstrap complete."
echo "    Magnolia is starting — allow 3-5 minutes for full initialisation."
echo "    Monitor progress: journalctl -u magnolia -f"
