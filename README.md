Uitlizar o comando completo para baixar o script e realizar a instalação:

curl -fsSL https://raw.githubusercontent.com/gokubr/scripts/main/upgrade-zabbix-agent-to-agent2-v7.sh -o /tmp/upgrade-zabbix-agent.sh && chmod +x /tmp/upgrade-zabbix-agent.sh && /tmp/upgrade-zabbix-agent.sh

Depois para checar se está tudo ok:

zabbix_agent2 -V
systemctl status zabbix-agent2
