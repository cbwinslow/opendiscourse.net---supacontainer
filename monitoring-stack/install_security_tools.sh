#!/bin/bash

# Exit on error and print each command
set -ex

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Installing Security and Monitoring Tools ===${NC}"

# Update package lists
echo -e "${YELLOW}Updating package lists...${NC}"
sudo apt-get update -y

# Install Cockpit for server management
echo -e "${YELLOW}Installing Cockpit...${NC}"
sudo apt-get install -y cockpit
sudo systemctl enable --now cockpit.socket

# Install Snort for network intrusion detection
echo -e "${YELLOW}Installing Snort...${NC}"
sudo apt-get install -y snort

# Configure Snort (basic configuration)
sudo cp /etc/snort/snort.lua /etc/snort/snort.lua.bak
sudo sed -i 's/HOME_NET = .*/HOME_NET = "95.217.106.172\/32"/' /etc/snort/snort.lua
sudo systemctl enable snort
sudo systemctl start snort

# Install ntopng for IP monitoring
echo -e "${YELLOW}Installing ntopng...${NC}"
sudo apt-get install -y ntopng

# Configure ntopng
sudo bash -c 'cat > /etc/ntopng/ntopng.conf << EOL
# ntopng configuration
-G=/var/run/ntopng.pid
--community
--local-networks=95.217.106.172/32
--disable-login=1
--http-port=3001
--https-port=3002
EOL'

sudo systemctl enable ntopng
sudo systemctl start ntopng

# Install cloudflared for Cloudflare WAF
echo -e "${YELLOW}Installing cloudflared...${NC}"
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo dpkg -i cloudflared-linux-amd64.deb
rm cloudflared-linux-amd64.deb

# Create systemd service for cloudflared
sudo bash -c 'cat > /etc/systemd/system/cloudflared.service << EOL
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloudflared tunnel --no-autoupdate run
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOL'

# Start cloudflared service
sudo systemctl daemon-reload
sudo systemctl enable cloudflared

# Install Wazuh agent for security monitoring
echo -e "${YELLOW}Installing Wazuh agent...${NC}"
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import && sudo chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee -a /etc/apt/sources.list.d/wazuh.list
sudo apt-get update -y
sudo apt-get install -y wazuh-agent

# Configure Wazuh agent
sudo sed -i 's/^enabled=.*/enabled=yes/' /var/ossec/etc/ossec.conf
sudo systemctl daemon-reload
sudo systemctl enable wazuh-agent
sudo systemctl start wazuh-agent

# Install and configure auditd for system call auditing
echo -e "${YELLOW}Configuring auditd...${NC}"
sudo apt-get install -y auditd audispd-plugins

# Configure auditd rules
sudo bash -c 'cat > /etc/audit/rules.d/audit.rules << EOL
# First rule - delete all
-D

# Increase the buffers to survive stress events
-b 8192

# Failure of auditd causes a kernel panic
-f 2

# Monitor file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k mounts

# Monitor file deletion events
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F auid>=1000 -F auid!=-1 -k delete

# Monitor file attribute changes
-a always,exit -F arch=b64 -S chmod -S fchmod -S fchmodat -F auid>=1000 -F auid!=-1 -F key=perm_mod

# Monitor file ownership changes
-a always,exit -F arch=b64 -S chown -S fchown -S fchownat -S lchown -F auid>=1000 -F auid!=-1 -F key=perm_mod

# Monitor successful file system mounts
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k mounts

# Monitor use of privileged commands
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=-1 -k privileged

# Monitor use of su command
-a always,exit -F path=/bin/su -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-priv_change

# Monitor use of passwd command
-a always,exit -F path=/usr/bin/passwd -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-passwd

# Monitor use of user management commands
-a always,exit -F path=/usr/sbin/useradd -F perm=x -F auid>=1000 -F auid!=-1 -k user_mgmt
-a always,exit -F path=/usr/sbin/userdel -F perm=x -F auid>=1000 -F auid!=-1 -k user_mgmt
-a always,exit -F path=/usr/sbin/usermod -F perm=x -F auid>=1000 -F auid!=-1 -k user_mgmt

# Monitor use of group management commands
-a always,exit -F path=/usr/sbin/groupadd -F perm=x -F auid>=1000 -F auid!=-1 -k group_mgmt
-a always,exit -F path=/usr/sbin/groupdel -F perm=x -F auid>=1000 -F auid!=-1 -k group_mgmt
-a always,exit -F path=/usr/sbin/groupmod -F perm=x -F auid>=1000 -F auid!=-1 -k group_mgmt

# Monitor use of crontab command
-a always,exit -F path=/usr/bin/crontab -F perm=x -F auid>=1000 -F auid!=-1 -k crontab

# Monitor use of at command
-a always,exit -F path=/usr/bin/at -F perm=x -F auid>=1000 -F auid!=-1 -k at

# Monitor use of ssh-keysign
-a always,exit -F path=/usr/lib/openssh/ssh-keysign -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-ssh

# Monitor use of sudoedit
-a always,exit -F path=/usr/bin/sudoedit -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-sudoedit

# Monitor use of pkexec
-a always,exit -F path=/usr/bin/pkexec -F perm=x -F auid>=1000 -F auid!=-1 -k privileged-pkexec
EOL'

# Restart auditd to apply new rules
sudo systemctl restart auditd

# Install and configure osquery for system introspection
echo -e "${YELLOW}Installing osquery...${NC}"
sudo apt-get install -y wget
wget -O - https://pkg.osquery.io/deb/gpg | sudo apt-key add -
echo "deb [arch=amd64] https://pkg.osquery.io/deb deb main" | sudo tee /etc/apt/sources.list.d/osquery.list
sudo apt-get update -y
sudo apt-get install -y osquery

# Configure osquery
sudo cp /etc/osquery/osquery.example.conf /etc/osquery/osquery.conf
sudo systemctl enable osqueryd
sudo systemctl start osqueryd

# Install and configure syslog-ng for centralized logging
echo -e "${YELLOW}Configuring syslog-ng...${NC}"
sudo apt-get install -y syslog-ng

# Configure syslog-ng to forward logs to Loki
sudo bash -c 'cat > /etc/syslog-ng/conf.d/loki.conf << EOL
destination d_loki {
  http(
    url("http://localhost:3100/loki/api/v1/push")
    method("POST")
    headers("Content-Type: application/json")
    body("{ \"streams\": [ { \"stream\": { \"host\": \"$HOST\" }, \"values\": [ [ \"$UNIXTIME\"000000000\", \"$MESSAGE\" ] ] } ] }")
  );
};

log {
  source(s_src);
  destination(d_loki);
};
EOL'

# Restart syslog-ng
sudo systemctl restart syslog-ng

# Install and configure Filebeat for log forwarding
echo -e "${YELLOW}Installing Filebeat...${NC}"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
sudo apt-get update -y
sudo apt-get install -y filebeat

# Configure Filebeat to send to OpenSearch
sudo bash -c 'cat > /etc/filebeat/filebeat.yml << EOL
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/*.log
    - /var/log/nginx/*.log
    - /var/log/syslog
    - /var/log/auth.log
    - /var/log/audit/audit.log
    - /var/log/ntopng/*.log

output.elasticsearch:
  hosts: ["localhost:9200"]
  username: "${OPENSEARCH_USER:-admin}"
  password: "${OPENSEARCH_PASSWORD}"

setup.ilm.enabled: false

setup.template.name: "filebeat"
setup.template.pattern: "filebeat-*"
setup.template.overwrite: true
EOL'

# Start and enable Filebeat
sudo systemctl enable filebeat
sudo systemctl start filebeat

# Install and configure Promtail for log shipping to Loki
echo -e "${YELLOW}Installing Promtail...${NC}"
wget https://github.com/grafana/loki/releases/download/v2.6.1/promtail-linux-amd64.zip
sudo apt-get install -y unzip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail

# Create Promtail config
sudo bash -c 'cat > /etc/promtail-config.yaml << EOL
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
- job_name: system
  static_configs:
  - targets:
      - localhost
    labels:
      job: varlogs
      __path__: /var/log/*log

  - targets:
      - localhost
    labels:
      job: nginx
      __path__: /var/log/nginx/*log

  - targets:
      - localhost
    labels:
      job: auth
      __path__: /var/log/auth.log

  - targets:
      - localhost
    labels:
      job: audit
      __path__: /var/log/audit/audit.log

  - targets:
      - localhost
    labels:
      job: kernel
      __path__: /var/log/kern.log
EOL'

# Create systemd service for Promtail
sudo bash -c 'cat > /etc/systemd/system/promtail.service << EOL
[Unit]
Description=Promtail service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/promtail -config.file=/etc/promtail-config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOL'

# Start and enable Promtail
sudo systemctl daemon-reload
sudo systemctl enable promtail
sudo systemctl start promtail

# Create a script to check security status
echo -e "${YELLOW}Creating security check script...${NC}"
sudo bash -c 'cat > /usr/local/bin/security-check << EOL
#!/bin/bash

echo "=== Security Status Check ==="
echo "\n[+] Running processes as root:"
ps -ef | grep "^root" | grep -v "\[" | grep -v "sshd\|systemd\|cron\|rsyslog\|dbus\|ntp\|ntpd\|rpc\|sasl\|postfix\|dovecot\|postgres\|mysql\|mongo\|redis\|memcached\|beanstalkd\|rabbitmq\|elasticsearch\|logstash\|kibana\|grafana\|prometheus\|node_exporter\|blackbox_exporter\|alertmanager\|loki\|promtail" || echo "No unexpected root processes found"

echo "\n[+] Listening ports:"
ss -tulnp | grep -E "0.0.0.0|:::"

echo "\n[+] Failed login attempts (last 10):"
sudo grep "Failed password" /var/log/auth.log | tail -n 10

echo "\n[+] Successful logins (last 10):"
sudo grep "session opened" /var/log/auth.log | tail -n 10

echo "\n[+] Sudo commands (last 10):"
sudo grep "sudo:" /var/log/auth.log | grep -v "pam_unix" | tail -n 10

echo "\n[+] Unusual processes:"
ps aux | grep -E "(ncat|nc|socat|wget|curl|bash|sh|perl|python|ruby|php|java|node|go|gcc|g\+\+|make|gdb|strace|ltrace|tcpdump|wireshark|nessus|nikto|metasploit|msf|nmap|nikto|sqlmap|hydra|john|hashcat|aircrack|ettercap|beef|armitage|veil|empire|cobaltstrike|mimikatz|powershell|python3|python2|ruby|perl|php|java|node|go|gcc|g\+\+|make|gdb|strace|ltrace|tcpdump|wireshark|nessus|nikto|metasploit|msf|nmap|nikto|sqlmap|hydra|john|hashcat|aircrack|ettercap|beef|armitage|veil|empire|cobaltstrike|mimikatz|powershell)" | grep -v "grep" || echo "No unusual processes found"

echo "\n[+] Large files (top 10):"
sudo find / -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -hr | head -n 10

echo "\n[+] SUID/SGID files:"
sudo find / -type f \( -perm -4000 -o -perm -2000 \) -exec ls -ld {} \; 2>/dev/null || echo "No SUID/SGID files found"

echo "\n[+] World-writable directories:"
sudo find / -type d -perm -2 ! -path "/proc/*" ! -path "/sys/*" ! -path "/run/*" ! -path "/dev/*" ! -path "/var/lib/*" ! -path "/var/log/*" 2>/dev/null || echo "No world-writable directories found"

echo "\n[+] Crontab entries:"
sudo crontab -l 2>/dev/null || echo "No crontab entries found"

echo "\n[+] Active services:"
systemctl list-units --type=service --state=running

echo "\n=== Security check completed ==="
EOL'

# Make the security check script executable
sudo chmod +x /usr/local/bin/security-check

# Create a cron job to run the security check daily
echo -e "${YELLOW}Setting up daily security check...${NC}"
(sudo crontab -l 2>/dev/null; echo "0 3 * * * /usr/local/bin/security-check | mail -s "[$(hostname)] Daily Security Report" root") | sudo crontab -

# Install and configure rkhunter for rootkit detection
echo -e "${YELLOW}Installing rkhunter...${NC}"
sudo apt-get install -y rkhunter
sudo rkhunter --update
sudo rkhunter --propupd

# Create a cron job to run rkhunter weekly
(sudo crontab -l 2>/dev/null; echo "0 4 * * 0 /usr/bin/rkhunter --cronjob --update --quiet") | sudo crontab -

# Install and configure chkrootkit for rootkit detection
echo -e "${YELLOW}Installing chkrootkit...${NC}"
sudo apt-get install -y chkrootkit

# Create a cron job to run chkrootkit weekly
(sudo crontab -l 2>/dev/null; echo "0 5 * * 0 /usr/sbin/chkrootkit | mail -s "[$(hostname)] chkrootkit Report" root") | sudo crontab -

# Install and configure lynis for security auditing
echo -e "${YELLow}Installing lynis...${NC}"
sudo apt-get install -y lynis

# Create a cron job to run lynis weekly
(sudo crontab -l 2>/dev/null; echo "0 6 * * 0 /usr/sbin/lynis audit system --cronjob | mail -s "[$(hostname)] Lynis Security Audit" root") | sudo crontab -

# Install and configure aide for file integrity monitoring
echo -e "${YELLOW}Installing AIDE...${NC}"
sudo apt-get install -y aide aide-common

# Initialize AIDE database
sudo aideinit -y -f

# Create a cron job to run AIDE daily
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/aide.wrapper --check | mail -s "[$(hostname)] AIDE Check" root") | sudo crontab -

# Install and configure clamav for malware scanning
echo -e "${YELLOW}Installing ClamAV...${NC}"
sudo apt-get install -y clamav clamav-daemon clamav-freshclam

# Update ClamAV virus definitions
sudo freshclam

# Create a cron job to run ClamAV daily
(sudo crontab -l 2>/dev/null; echo "0 1 * * * /usr/bin/clamscan -r --bell -i / | mail -s "[$(hostname)] ClamAV Scan Report" root") | sudo crontab -

# Install and configure logwatch for log analysis
echo -e "${YELLOW}Installing Logwatch...${NC}"
sudo apt-get install -y logwatch

# Configure Logwatch to send daily reports
sudo bash -c 'cat > /etc/cron.daily/00logwatch << EOL
#!/bin/bash
/usr/sbin/logwatch --output mail --mailto root --detail high
EOL'
sudo chmod +x /etc/cron.daily/00logwatch

# Install and configure psad for port scan detection
echo -e "${YELLOW}Installing psad...${NC}"
sudo apt-get install -y psad

# Configure psad
sudo sed -i 's/^ENABLE_AUTO_IDS .*/ENABLE_AUTO_IDS Y;/' /etc/psad/psad.conf
sudo sed -i 's/^AUTO_IDS_DANGER_LEVEL .*/AUTO_IDS_DANGER_LEVEL 4;/' /etc/psad/psad.conf
sudo sed -i 's/^EMAIL_ALERT_DANGER_LEVEL .*/EMAIL_ALERT_DANGER_LEVEL 4;/' /etc/psad/psad.conf

# Start and enable psad
sudo psad --sig-update
sudo psad -H
sudo systemctl enable psad
sudo systemctl start psad

# Install and configure rkhunter for rootkit detection
echo -e "${YELLOW}Configuring rkhunter...${NC}"
sudo sed -i 's/^CRON_DAILY_RUN=.*/CRON_DAILY_RUN="yes"/' /etc/default/rkhunter
sudo sed -i 's/^CRON_DB_UPDATE=.*/CRON_DB_UPDATE="yes"/' /etc/default/rkhunter
sudo sed -i 's/^APT_AUTOGEN=.*/APT_AUTOGEN="yes"/' /etc/default/rkhunter

# Update rkhunter database
sudo rkhunter --update
sudo rkhunter --propupd

# Install and configure chkrootkit for rootkit detection
echo -e "${YELLOW}Configuring chkrootkit...${NC}"

# Create a cron job to run chkrootkit weekly
(sudo crontab -l 2>/dev/null; echo "0 4 * * 0 /usr/sbin/chkrootkit | mail -s "[$(hostname)] chkrootkit Report" root") | sudo crontab -

# Install and configure lynis for security auditing
echo -e "${YELLOW}Configuring lynis...${NC}"

# Create a cron job to run lynis weekly
(sudo crontab -l 2>/dev/null; echo "0 5 * * 0 /usr/sbin/lynis audit system --cronjob | mail -s "[$(hostname)] Lynis Security Audit" root") | sudo crontab -

# Install and configure aide for file integrity monitoring
echo -e "${YELLOW}Configuring AIDE...${NC}"

# Initialize AIDE database
sudo aideinit -y -f

# Create a cron job to run AIDE daily
(sudo crontab -l 2>/dev/null; echo "0 2 * * * /usr/bin/aide.wrapper --check | mail -s "[$(hostname)] AIDE Check" root") | sudo crontab -

# Install and configure clamav for malware scanning
echo -e "${YELLOW}Configuring ClamAV...${NC}"

# Update ClamAV virus definitions
sudo freshclam

# Create a cron job to run ClamAV daily
(sudo crontab -l 2>/dev/null; echo "0 1 * * * /usr/bin/clamscan -r --bell -i / | mail -s "[$(hostname)] ClamAV Scan Report" root") | sudo crontab -

# Install and configure logwatch for log analysis
echo -e "${YELLOW}Configuring Logwatch...${NC}"

# Configure Logwatch to send daily reports
sudo bash -c 'cat > /etc/cron.daily/00logwatch << EOL
#!/bin/bash
/usr/sbin/logwatch --output mail --mailto root --detail high
EOL'
sudo chmod +x /etc/cron.daily/00logwatch

# Install and configure psad for port scan detection
echo -e "${YELLOW}Configuring psad...${NC}"

# Configure psad
sudo sed -i 's/^ENABLE_AUTO_IDS .*/ENABLE_AUTO_IDS Y;/' /etc/psad/psad.conf
sudo sed -i 's/^AUTO_IDS_DANGER_LEVEL .*/AUTO_IDS_DANGER_LEVEL 4;/' /etc/psad/psad.conf
sudo sed -i 's/^EMAIL_ALERT_DANGER_LEVEL .*/EMAIL_ALERT_DANGER_LEVEL 4;/' /etc/psad/psad.conf

# Start and enable psad
sudo psad --sig-update
sudo psad -H
sudo systemctl enable psad
sudo systemctl start psad

echo -e "\n${GREEN}=== Security and Monitoring Tools Installation Complete ===${NC}"
echo -e "\nAccess the following services:"
echo -e "- Cockpit:              http://95.217.106.172:9090"
echo -e "- ntopng:               http://95.217.106.172:3001"
echo -e "- Grafana:              http://95.217.106.172:3000"
echo -e "- Prometheus:           http://95.217.106.172:9090"
echo -e "- RabbitMQ Management:  http://95.217.106.172:15672"
echo -e "- OpenSearch:           http://95.217.106.172:9200"
echo -e "- AI Orchestrator API:  http://95.217.106.172:8000"
echo -e "\nNext steps:"
echo -e "1. Configure Cloudflare WAF by running: cloudflared tunnel login"
echo -e "2. Create a tunnel: cloudflared tunnel create monitoring-tunnel"
echo -e "3. Configure the tunnel with your domain and start it"
echo -e "4. Review the security check report: /usr/local/bin/security-check"
