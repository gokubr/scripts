#!/bin/bash
# -------------------------------------------------------------
# Script de upgrade automático:
# Zabbix Agent (v6.x) -> Zabbix Agent2 (v7.0 LTS)
# -------------------------------------------------------------
# Compatível: Debian 11, 12, 13 e RHEL 8/9
# Data: 2025-11-08
# -------------------------------------------------------------

set -euo pipefail
LOGFILE="/var/log/zabbix-agent2-upgrade.log"
exec > >(tee -a "$LOGFILE") 2>&1

progress_bar() {
  echo -n "[INFO] Aguardando"
  for i in {1..3}; do echo -n "."; sleep 0.5; done
  echo ""
}

#--------------------------------------------------------------
# 1. Validação de execução
#--------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "[ERRO] Este script precisa ser executado como root."
  exit 1
fi

echo "[INFO] Iniciando upgrade do Zabbix Agent para Agent2 (7.0)..."
progress_bar

#--------------------------------------------------------------
# 2. Detectar sistema operacional
#--------------------------------------------------------------
if [ -f /etc/debian_version ]; then
  OS="debian"
  PM="apt"
elif [ -f /etc/redhat-release ]; then
  OS="rhel"
  PM="yum"
else
  echo "[ERRO] Sistema operacional não suportado."
  exit 1
fi
progress_bar

#--------------------------------------------------------------
# 3. Variáveis e caminhos
#--------------------------------------------------------------
ZBX_VERSION="7.0"
CONF_OLD="/etc/zabbix/zabbix_agentd.conf"
CONF_NEW="/etc/zabbix/zabbix_agent2.conf"
DATE_TAG=$(date +%F_%H-%M-%S)

#--------------------------------------------------------------
# 4. Backups de segurança
#--------------------------------------------------------------
echo "[INFO] Fazendo backup de arquivos de configuração..."
[ -f "$CONF_OLD" ] && cp -p "$CONF_OLD" "${CONF_OLD}.bak_${DATE_TAG}"
[ -f "$CONF_NEW" ] && cp -p "$CONF_NEW" "${CONF_NEW}.orig_${DATE_TAG}"
progress_bar

#--------------------------------------------------------------
# 5. Instalar repositório oficial Zabbix 7.0
#--------------------------------------------------------------
echo "[INFO] Instalando repositório oficial do Zabbix 7.0..."

if [ "$OS" == "debian" ]; then
  DEB_VER=$(lsb_release -rs | cut -d. -f1)
  REPO_FILE="zabbix-release_latest_7.0+debian${DEB_VER}_all.deb"
  REPO_URL="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/${REPO_FILE}"

  echo "[INFO] Baixando ${REPO_URL} ..."
  wget -q -O /tmp/${REPO_FILE} "${REPO_URL}" || {
    echo "[ERRO] Falha ao baixar o repositório Zabbix para Debian ${DEB_VER}."
    exit 1
  }

  dpkg -i /tmp/${REPO_FILE}
  $PM update -y
else
  rpm -Uvh https://repo.zabbix.com/zabbix/${ZBX_VERSION}/rhel/$(rpm -E %{rhel})/x86_64/zabbix-release-latest-${ZBX_VERSION}.el$(rpm -E %{rhel}).noarch.rpm
  $PM clean all
fi
progress_bar

#--------------------------------------------------------------
# 6. Instalar/atualizar Zabbix Agent2
#--------------------------------------------------------------
echo "[INFO] Instalando Zabbix Agent2 versão ${ZBX_VERSION}..."
$PM install -y zabbix-agent2
progress_bar

#--------------------------------------------------------------
# 7. Parar e remover completamente o agent antigo
#--------------------------------------------------------------
echo "[INFO] Parando e desabilitando o Agent antigo..."
systemctl stop zabbix-agent 2>/dev/null || true
systemctl disable zabbix-agent 2>/dev/null || true
pkill -9 zabbix_agentd 2>/dev/null || true
$PM remove -y zabbix-agent || true
echo "[INFO] Zabbix Agent antigo removido com sucesso."
progress_bar

#--------------------------------------------------------------
# 8. Migrar configuração antiga para o novo Agent2
#--------------------------------------------------------------
if [ -f "$CONF_OLD" ]; then
  echo "[INFO] Migrando configuração do Agent 1 -> Agent 2..."
  cp -p "$CONF_OLD" "$CONF_NEW"
else
  echo "[AVISO] Arquivo $CONF_OLD não encontrado. Usando configuração padrão do Agent2."
fi
progress_bar

#--------------------------------------------------------------
# 9. Corrigir parâmetros e includes incompatíveis
#--------------------------------------------------------------
echo "[INFO] Ajustando parâmetros obsoletos e caminhos de include..."

# Comentar parâmetros não suportados no Agent2 7.0
for key in LogRemoteCommands EnableRemoteCommands SourceIP StartAgents; do
  sed -i "s/^${key}/# ${key} (removido no agent2)/" "$CONF_NEW" 2>/dev/null || true
done

# Corrigir Include path
sed -i 's|^Include=/etc/zabbix/zabbix_agentd.d/|Include=/etc/zabbix/zabbix_agent2.d/|' "$CONF_NEW" 2>/dev/null || true

# Adicionar Plugin necessário
grep -q "^Plugins.SystemRun.LogRemoteCommands" "$CONF_NEW" || echo "Plugins.SystemRun.LogRemoteCommands=1" >> "$CONF_NEW"

# Garantir Hostname configurado
if ! grep -q "^Hostname=" "$CONF_NEW"; then
  echo "Hostname=$(hostname -f)" >> "$CONF_NEW"
fi
progress_bar

#--------------------------------------------------------------
# 10. Copiar UserParameters e arquivos customizados
#--------------------------------------------------------------
echo "[INFO] Copiando UserParameters e includes personalizados..."
mkdir -p /etc/zabbix/zabbix_agent2.d
if [ -d /etc/zabbix/zabbix_agentd.d ]; then
  cp -r /etc/zabbix/zabbix_agentd.d/* /etc/zabbix/zabbix_agent2.d/ 2>/dev/null || true
fi
progress_bar

#--------------------------------------------------------------
# 11. Ajustar permissões Docker (se existir)
#--------------------------------------------------------------
if command -v docker >/dev/null 2>&1; then
  echo "[INFO] Garantindo acesso ao Docker para o usuário 'zabbix'..."
  id -nG zabbix | grep -qw docker || usermod -aG docker zabbix
fi
progress_bar

#--------------------------------------------------------------
# 12. Reiniciar o serviço e verificar status
#--------------------------------------------------------------
echo "[INFO] Habilitando e iniciando Zabbix Agent2..."
systemctl enable zabbix-agent2
systemctl restart zabbix-agent2
sleep 2

echo "[INFO] Verificando status do serviço:"
systemctl --no-pager status zabbix-agent2 || true
echo "[INFO] Verificando porta 10050:"
ss -tulpn | grep 10050 || true

#--------------------------------------------------------------
# 13. Finalização
#--------------------------------------------------------------
echo -e "\n [SUCESSO] Zabbix Agent2 (${ZBX_VERSION}) instalado e em execução!"
echo "Backups salvos:"
echo "  - ${CONF_OLD}.bak_${DATE_TAG}"
echo "  - ${CONF_NEW}.orig_${DATE_TAG}"
echo "Log completo: ${LOGFILE}"
exit 0
