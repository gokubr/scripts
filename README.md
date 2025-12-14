Uitlizar o comando completo para baixar o script e realizar a instalação:

curl -fsSL https://raw.githubusercontent.com/gokubr/scripts/main/upgrade-zabbix-agent-to-agent2-v7.sh -o /tmp/upgrade-zabbix-agent.sh && chmod +x /tmp/upgrade-zabbix-agent.sh && /tmp/upgrade-zabbix-agent.sh

Depois para checar se está tudo ok:

zabbix_agent2 -V
systemctl status zabbix-agent2

#######################################################
AJUSTES ZABBIX PROXY 7.0
#######################################################

mkdir -p /opt/proxy/docker/mysql

nano mysql/my.cnf

[mysqld]

########################################
# INNODB - CACHE DE DADOS
########################################

# Quantidade de memoria dedicada ao cache do InnoDB (dados + índices).
# Este e o principal fator de performance do MySQL para o Zabbix Proxy.
#
# Regra pratica:
# - 50% a 70% da RAM total da VM
# - Aqui: VM com 8 GB de RAM → 8G e aceitavel porque:
#   - O proxy nao mantem historico longo
#   - O housekeeping do proxy esta desativado
#
# IMPORTANTE:
# Se a VM tiver outros serviços pesados, reduzir para 6G.
innodb_buffer_pool_size=8G

########################################
# INNODB - LOG DE REDO (MySQL 8+)
########################################

# Capacidade total do redo log do InnoDB.
# Substitui innodb_log_file_size + innodb_log_files_in_group (deprecated).
#
# Impacto:
# - Reduz flush frequente em disco
# - Melhora escrita em cargas intensas (SNMP / bulk data)
#
# Valor recomendado:
# - 512M a 2G para proxies medios/grandes
# - 1G e um bom equilíbrio entre performance e tempo de recovery
innodb_redo_log_capacity=1G

########################################
# DURABILIDADE x PERFORMANCE
########################################
# Controla quando o InnoDB grava o log em disco.
#
# Valores:
# 0 = maximo desempenho, risco maior em crash
# 1 = maxima seguranca (default, mais lento)
# 2 = equilibrio (RECOMENDADO para Zabbix Proxy)
#
# Com valor 2:
# - Commit a cada transacao
# - Flush fisico a cada 1 segundo
#
# Aceitavel para proxy (dados são temporarios).
innodb_flush_log_at_trx_commit=2

# Controla quando o binlog é sincronizado em disco.
#
# 0 = deixa o SO decidir (mais rapido)
# 1 = flush a cada transacao (mais seguro)
#
# Como o proxy NAO usa replicacao:
# - Seguranca nao e critica
# - Performance e prioridade
sync_binlog=0

########################################
# METODO DE ESCRITA EM DISCO
########################################
# Define como o InnoDB escreve dados no disco.
#
# O_DIRECT:
# - Evita double caching (RAM do MySQL + cache do SO)
# - Reduz uso desnecessario de memoria
# - Mais previsivel em ambientes de virtualizacao
#
# RECOMENDADO para:
# - Proxmox
# - KVM
innodb_flush_method=O_DIRECT


 chown root:root mysql/my.cnf
 chmod 644 mysql/my.cnf

AJUSTAR docker compose

 volumes:
      - ${MYSQL_DATA_DIR}:/var/lib/mysql:rw
      - ./mysql:/etc/mysql/conf.d:ro

AJUSTAR env/.env_proxy

      ABAIXO DO HOSTNAME:

# Permite e registra comandos remotos executados pelo servidor
ZBX_ENABLEREMOTECOMMANDS=1
ZBX_LOGREMOTECOMMANDS=1

# Buffer offline em horas (dados mantidos se o servidor ficar inacessivel)
ZBX_PROXYOFFLINEBUFFER=72

# Frequencia de envio de heartbeat ao servidor (segundos)
ZBX_PROXYHEARTBEATFREQUENCY=60

# Frequencia de atualizacao da configuracao (segundos)
ZBX_CONFIGFREQUENCY=60

# Frequencia de envio de dados ao servidor (segundos)
ZBX_DATASENDERFREQUENCY=30

# Numero de pollers simultaneos
ZBX_STARTPOLLERS=60

# Numero de pollers para hosts inalcancaveis
ZBX_STARTPOLLERSUNREACHABLE=10

# Numero de trappers (recebe dados do servidor)
ZBX_STARTTRAPPERS=3

# Numero de pingers (checagem ICMP)
ZBX_STARTPINGERS=3

# Numero de discoverers (descobertas automaticas)
ZBX_STARTDISCOVERERS=3

# Habilita recebimento de traps SNMP
ZBX_ENABLE_SNMP_TRAPS=true

# Frequencia de housekeeping no banco do proxy (horas)
# O proxy nao armazena dados permanentemente
# Dados enviados ao server sao removidos automaticamente
# ProxyOfflineBuffer limita o backlog maximo
# Desativar housekeeping reduz carga periodica no banco
ZBX_HOUSEKEEPINGFREQUENCY=0

# Tamanho do cache de configuracao
ZBX_CACHESIZE=512M

# Numero de threads de sincronizacao com o banco
ZBX_STARTDBSYNCERS=6

# Tempo limite para execucao de checks (segundos)
ZBX_TIMEOUT=10

# Numero de threads de preprocessamento
# Executa LLD, expressoes, regex, JavaScript, normalizacao SNMP
# Um dos maiores consumidores de CPU no Zabbix
# Valor controlado evita overthread e reduz load
ZBX_STARTPREPROCESSORS=15



