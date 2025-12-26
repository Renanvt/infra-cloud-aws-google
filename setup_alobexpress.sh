#!/bin/bash
set -e

# ==========================================
#  🚀 INFRASTRUCTURE SETUP
#  Version: 3.1.0 - MULTI-CLOUD SWARM (AWS & GCP)
#  Author: AlobExpress Team
#  Updated: 2025-12-25
# ==========================================

# ===== CORES ANSI =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Ícones
CHECK="${GREEN}✓${RESET}"
CROSS="${RED}✗${RESET}"
ARROW="${CYAN}→${RESET}"
WARN="${YELLOW}⚠${RESET}"
INFO="${BLUE}ℹ${RESET}"
ROCKET="${MAGENTA}🚀${RESET}"

# ===== VARIÁVEIS GLOBAIS =====
IS_AWS=false
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
S3_REGION=""
S3_BUCKET_NAME=""

# ===== FUNÇÕES DE UI =====
print_banner() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}║${RESET}  ${BOLD}${MAGENTA}🚀 INFRASTRUCTURE SETUP v3.1.0${RESET}                           ${CYAN}║${RESET}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${CYAN}║${RESET}  ${DIM}Suporte Multi-Cloud: AWS & GCP (Unified Swarm)${RESET}          ${CYAN}║${RESET}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_step() {
    echo -e "\n${BOLD}${BLUE}▶${RESET} ${BOLD}$1${RESET}"
}

print_success() {
    echo -e "  ${CHECK} ${GREEN}$1${RESET}"
}

print_error() {
    echo -e "  ${CROSS} ${RED}$1${RESET}"
}

print_warning() {
    echo -e "  ${WARN} ${YELLOW}$1${RESET}"
}

print_info() {
    echo -e "  ${INFO} ${CYAN}$1${RESET}"
}

spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [${CYAN}%c${RESET}] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# ===== FUNÇÕES AUXILIARES =====
install_docker() {
    if ! command -v docker &> /dev/null; then
        print_info "Instalando Docker..."
        {
            curl -fsSL https://get.docker.com -o get-docker.sh
            sh get-docker.sh
            systemctl enable docker
            systemctl start docker
        } > /tmp/docker_install.log 2>&1 &
        spinner $!
        print_success "Docker Instalado"
    else
        print_success "Docker já está instalado"
    fi
}

# ===== ARQUITETURA SWARM (COMUM: AWS & GCP) =====
# Esta função é agnóstica de nuvem e é chamada tanto pelo setup_aws quanto pelo setup_gcp
setup_swarm_architecture() {
    # Inicializar Swarm
    if ! docker info | grep -q "Swarm: active"; then
        print_info "Inicializando Docker Swarm..."
        docker swarm init > /dev/null 2>&1 || print_warning "Swarm já iniciado ou erro ao iniciar"
    fi
    
    # Criar rede pública
    if ! docker network ls | grep -q "network_swarm_public"; then
        docker network create --driver overlay --attachable network_swarm_public
        print_success "Rede 'network_swarm_public' criada"
    fi

    # Criar volumes externos necessários
    print_info "Criando volumes persistentes..."
    docker volume create volume_swarm_shared >/dev/null
    docker volume create volume_swarm_certificates >/dev/null
    docker volume create portainer_data >/dev/null
    docker volume create postgres_data >/dev/null
    docker volume create redis_data >/dev/null
    print_success "Volumes criados"

    # Passo 1.1 Configuração Multi-VM (Labeling)
    print_step "CONFIGURAÇÃO DE NÓS (LABELING)"
    echo -e "${YELLOW}Aplicando label 'app=n8n' neste nó (Manager)...${RESET}"
    docker node update --label-add app=n8n $(hostname) >/dev/null 2>&1
    print_success "Label 'app=n8n' aplicada"

    # Aviso DNS Cloudflare
    print_step "VERIFICAÇÃO DE DNS (CLOUDFLARE)"
    echo -e "${YELLOW}Antes de continuar, certifique-se de que os apontamentos DNS foram feitos:${RESET}"
    echo -e "1. Crie um registro A para o IP desta VM"
    echo -e "2. Crie CNAMEs para os serviços (painel, editor, webhook, evolution) apontando para o registro A"
    echo -e "3. Exemplo de configuração CNAME: ${BOLD}evolution.seu-dominio.com.br -> manager.seu-dominio.com.br${RESET}"
    echo -e "4. Use 'DNS Only' (Nuvem Cinza) no Cloudflare inicialmente para gerar SSL"
    read -p "$(echo -e ${BOLD}${GREEN}"Os DNS estão configurados corretamente? (s/n): "${RESET})" DNS_CONFIRM
    if [[ ! "$DNS_CONFIRM" =~ ^(s|S|sim|SIM)$ ]]; then 
        print_error "Configure o DNS e execute novamente."
        exit 0
    fi

    # Coleta de Dados
    print_step "PASSO 2: DEPLOY DOS SERVIÇOS - CONFIGURAÇÃO"
    
    read -p "$(echo -e ${CYAN}"📧 E-mail para SSL (Traefik): "${RESET})" TRAEFIK_EMAIL
    
    echo -e "\n${BOLD}${MAGENTA}=== PORTAINER ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Portainer (ex: painel.seu-dominio.com): "${RESET})" PORTAINER_DOMAIN
    
    echo -e "\n${BOLD}${MAGENTA}=== BANCO DE DADOS ===${RESET}"
    read -sp "$(echo -e ${CYAN}"🔒 Senha para o PostgreSQL: "${RESET})" POSTGRES_PASSWORD
    echo ""
    read -sp "$(echo -e ${CYAN}"🔒 Senha para o Redis: "${RESET})" REDIS_PASSWORD
    echo ""

    echo -e "\n${BOLD}${MAGENTA}=== RABBITMQ ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio do RabbitMQ (ex: rabbitmq.seu-dominio.com): "${RESET})" RABBITMQ_DOMAIN
    read -p "$(echo -e ${CYAN}"👤 Usuário do RabbitMQ (Enter para 'admin'): "${RESET})" RABBITMQ_USER
    if [ -z "$RABBITMQ_USER" ]; then
        RABBITMQ_USER="admin"
        print_info "Usuário definido como: admin"
    fi
    read -sp "$(echo -e ${CYAN}"🔒 Senha do RabbitMQ: "${RESET})" RABBITMQ_PASSWORD
    echo ""
    
    echo -e "\n${BOLD}${MAGENTA}=== N8N ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Editor N8N (ex: editor.seu-dominio.com): "${RESET})" N8N_EDITOR_DOMAIN
    read -p "$(echo -e ${CYAN}"🌍 Domínio do Webhook N8N (ex: webhook.seu-dominio.com): "${RESET})" N8N_WEBHOOK_DOMAIN
    read -p "$(echo -e ${CYAN}"🔑 N8N Encryption Key (ex: gere uma aleatória): "${RESET})" N8N_ENCRYPTION_KEY
    
    if [ -z "$N8N_ENCRYPTION_KEY" ]; then
        N8N_ENCRYPTION_KEY=$(openssl rand -hex 16)
        print_info "Chave gerada automaticamente: $N8N_ENCRYPTION_KEY"
    fi

    echo -e "\n${BOLD}${MAGENTA}=== EVOLUTION API ===${RESET}"
    read -p "$(echo -e ${CYAN}"🌍 Domínio da Evolution API (ex: evolution.seu-dominio.com): "${RESET})" EVOLUTION_DOMAIN
    read -p "$(echo -e ${CYAN}"🔑 Evolution API Global Key (Enter para gerar automática): "${RESET})" EVOLUTION_API_KEY
    
    if [ -z "$EVOLUTION_API_KEY" ]; then
        EVOLUTION_API_KEY=$(openssl rand -hex 16)
        print_info "Chave da Evolution gerada automaticamente: $EVOLUTION_API_KEY"
    fi

    echo -e "\n${BOLD}${MAGENTA}=== AWS S3 (EVOLUTION) ===${RESET}"
    read -p "$(echo -e ${CYAN}"🪣 Deseja habilitar S3 para Evolution? (s/n): "${RESET})" ENABLE_S3_EVO
    
    EVO_S3_BLOCK=""
    if [[ "$ENABLE_S3_EVO" =~ ^(s|S|sim|SIM)$ ]]; then
        read -p "$(echo -e ${CYAN}"🗝️  S3 Access Key: "${RESET})" EVO_S3_ACCESS_KEY
        read -sp "$(echo -e ${CYAN}"🔒 S3 Secret Key: "${RESET})" EVO_S3_SECRET_KEY
        echo ""
        read -p "$(echo -e ${CYAN}"🪣 S3 Bucket Name: "${RESET})" EVO_S3_BUCKET
        read -p "$(echo -e ${CYAN}"🌍 S3 Endpoint (ex: s3.us-east-1.amazonaws.com): "${RESET})" EVO_S3_ENDPOINT
        
        EVO_S3_BLOCK=$(cat <<S3_BLOCK
      - S3_ENABLED=true
      - S3_ACCESS_KEY=${EVO_S3_ACCESS_KEY}
      - S3_SECRET_KEY=${EVO_S3_SECRET_KEY}
      - S3_BUCKET=${EVO_S3_BUCKET}
      - S3_PORT=443
      - S3_ENDPOINT=${EVO_S3_ENDPOINT}
      - S3_USE_SSL=true
S3_BLOCK
)
    else
        EVO_S3_BLOCK=$(cat <<S3_BLOCK
      - S3_ENABLED=false
S3_BLOCK
)
    fi

    echo -e "\n${BOLD}${MAGENTA}=== DIFY AI ===${RESET}"
    print_warning "⚠️  ATENÇÃO: Requisitos de Sistema para Dify AI"
    echo -e "   ${YELLOW}O Dify requer MÍNIMO de 2 vCPU e 2GB RAM adicionais.${RESET}"
    echo -e "   ${YELLOW}Considerando N8N, Evolution, Postgres, Redis e RabbitMQ, sua VM deve ter:${RESET}"
    echo -e "   ${BOLD}➜ Recomendado: 4 vCPU e 8GB RAM (ou mais)${RESET}"
    echo -e "   ${DIM}Se sua VM tiver menos recursos, os serviços podem falhar ou travar.${RESET}"
    echo ""
    read -p "$(echo -e ${CYAN}"🤖 Deseja habilitar o Dify? (s/n): "${RESET})" ENABLE_DIFY
    
    DIFY_S3_BLOCK=""
    if [[ "$ENABLE_DIFY" =~ ^(s|S|sim|SIM)$ ]]; then
        ENABLE_DIFY=true
        read -p "$(echo -e ${CYAN}"🌍 Domínio do Dify Web (ex: dify.seu-dominio.com): "${RESET})" DIFY_WEB_DOMAIN
        read -p "$(echo -e ${CYAN}"🌍 Domínio do Dify API (ex: api.dify.seu-dominio.com): "${RESET})" DIFY_API_DOMAIN
        
        print_warning "Lembre-se de criar os registros CNAME para:"
        echo -e "   1. ${BOLD}${DIFY_WEB_DOMAIN}${RESET} -> Apontando para o IP deste servidor"
        echo -e "   2. ${BOLD}${DIFY_API_DOMAIN}${RESET} -> Apontando para o IP deste servidor"
        echo ""

        read -p "$(echo -e ${CYAN}"🔑 Dify Secret Key (Enter para gerar automática): "${RESET})" DIFY_SECRET_KEY
        
        if [ -z "$DIFY_SECRET_KEY" ]; then
            DIFY_SECRET_KEY="sk-$(openssl rand -hex 20)"
            print_info "Secret Key gerada automaticamente: $DIFY_SECRET_KEY"
        fi

        read -p "$(echo -e ${CYAN}"🪣 Deseja habilitar S3 para Dify? (s/n): "${RESET})" ENABLE_S3_DIFY
        if [[ "$ENABLE_S3_DIFY" =~ ^(s|S|sim|SIM)$ ]]; then
            read -p "$(echo -e ${CYAN}"🗝️  S3 Access Key: "${RESET})" DIFY_S3_ACCESS_KEY
            read -sp "$(echo -e ${CYAN}"🔒 S3 Secret Key: "${RESET})" DIFY_S3_SECRET_KEY
            echo ""
            read -p "$(echo -e ${CYAN}"🪣 S3 Bucket Name: "${RESET})" DIFY_S3_BUCKET
            read -p "$(echo -e ${CYAN}"🌍 S3 Endpoint (ex: https://s3.us-east-1.amazonaws.com): "${RESET})" DIFY_S3_ENDPOINT
            read -p "$(echo -e ${CYAN}"🌍 S3 Region (ex: us-east-1): "${RESET})" DIFY_S3_REGION

            DIFY_S3_BLOCK=$(cat <<S3_BLOCK
      STORAGE_TYPE: s3
      S3_ENDPOINT: '${DIFY_S3_ENDPOINT}'
      S3_BUCKET_NAME: '${DIFY_S3_BUCKET}'
      S3_ACCESS_KEY: '${DIFY_S3_ACCESS_KEY}'
      S3_SECRET_KEY: '${DIFY_S3_SECRET_KEY}'
      S3_REGION: '${DIFY_S3_REGION}'
      S3_USE_SSL: 'true'
S3_BLOCK
)
        else
             DIFY_S3_BLOCK=$(cat <<S3_BLOCK
      STORAGE_TYPE: local
S3_BLOCK
)
        fi
    else
        ENABLE_DIFY=false
    fi

    # Geração dos Arquivos YAML
    print_step "GERANDO ARQUIVOS DE CONFIGURAÇÃO (YAML)"
    
    # 04.traefik.yaml
    cat <<EOF > 04.traefik.yaml
version: "3.7"

services:
  traefik:
    image: traefik:v3.6.4
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command:
      - "--api.dashboard=true"
      - "--providers.swarm=true"
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=network_swarm_public"
      - "--core.defaultRuleSyntax=v2"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.web.http.redirections.entryPoint.permanent=true"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencryptresolver.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencryptresolver.acme.email=${TRAEFIK_EMAIL}"
      - "--certificatesresolvers.letsencryptresolver.acme.storage=/etc/traefik/letsencrypt/acme.json"
      - "--log.level=INFO"
      - "--accesslog=true"
    deploy:
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.middlewares.redirect-https.redirectscheme.scheme=https"
        - "traefik.http.middlewares.redirect-https.redirectscheme.permanent=true"
        - "traefik.http.routers.http-catchall.rule=hostregexp(\`{host:.+}\`)"
        - "traefik.http.routers.http-catchall.entrypoints=web"
        - "traefik.http.routers.http-catchall.middlewares=redirect-https@swarm"
        - "traefik.http.routers.http-catchall.priority=1"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
      - "vol_certificates:/etc/traefik/letsencrypt"
    networks:
      - network_swarm_public
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host

volumes:
  vol_shared:
    external: true
    name: volume_swarm_shared
  vol_certificates:
    external: true
    name: volume_swarm_certificates

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 05.portainer.yaml
    cat <<EOF > 05.portainer.yaml
version: "3.7"

services:
  agent:
    image: portainer/agent:2.33.5
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - network_swarm_public
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:2.33.5
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - portainer_data:/data
    networks:
      - network_swarm_public
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_DOMAIN}\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"
        - "traefik.http.routers.portainer.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  network_swarm_public:
    external: true
    attachable: true
    name: network_swarm_public

volumes:
  portainer_data:
    external: true
    name: portainer_data
EOF

    # 06.postgres.yaml
    cat <<EOF > 06.postgres.yaml
version: "3.7"
services:
  postgres:
    image: postgres:16-alpine
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - PGDATA=/var/lib/postgresql/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

volumes:
  postgres_data:
    external: true
    name: postgres_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 07.redis.yaml
    cat <<EOF > 07.redis.yaml
version: "3.7"
services:
  redis:
    image: redis:7-alpine
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: redis-server --appendonly yes --port 6379 --requirepass ${REDIS_PASSWORD}
    networks:
      - network_swarm_public
    volumes:
      - redis_data:/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M

volumes:
  redis_data:
    external: true
    name: redis_data
networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 11.rabbitmq.yaml
    cat <<EOF > 11.rabbitmq.yaml
version: "3.7"

services:
  rabbitmq:
    image: rabbitmq:3-management-alpine
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    networks:
      - network_swarm_public
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASSWORD}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 512M
      labels:
        - traefik.enable=true
        - traefik.http.routers.rabbitmq.rule=Host(\`${RABBITMQ_DOMAIN}\`)
        - traefik.http.routers.rabbitmq.entrypoints=websecure
        - traefik.http.routers.rabbitmq.tls.certresolver=letsencryptresolver
        - traefik.http.services.rabbitmq.loadbalancer.server.port=15672
        - traefik.http.routers.rabbitmq.service=rabbitmq

volumes:
  rabbitmq_data:
    external: true
    name: rabbitmq_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # DEFINIÇÃO DE VARIÁVEIS N8N
    AWS_ENV=""
    if [ "$IS_AWS" = true ]; then
        AWS_ENV=$(cat <<AWS_BLOCK
      - AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
      - AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
      - S3_REGION=${S3_REGION}
      - S3_BUCKET_NAME=${S3_BUCKET_NAME}
AWS_BLOCK
)
    fi

    N8N_ENV_BLOCK=$(cat <<ENV_BLOCK
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
${AWS_ENV}
      - NODE_ENV=production
      - N8N_PAYLOAD_SIZE_MAX=16
      - N8N_LOG_LEVEL=info
      - GENERIC_TIMEZONE=America/Sao_Paulo
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_PORT=5678
      - N8N_HOST=${N8N_EDITOR_DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_EDITOR_DOMAIN}/
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${N8N_WEBHOOK_DOMAIN}/
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis
      - QUEUE_BULL_REDIS_PORT=6379
      - QUEUE_BULL_REDIS_DB=2
      - QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
      - EXECUTIONS_DATA_PRUNE=true
      - EXECUTIONS_DATA_MAX_AGE=336
ENV_BLOCK
)

    # 08.n8n-editor.yaml
    cat <<EOF > 08.n8n-editor.yaml
version: "3.7"
services:
  n8n_editor:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: start
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.n8n_editor.rule=Host(\`${N8N_EDITOR_DOMAIN}\`)"
        - "traefik.http.routers.n8n_editor.entrypoints=websecure"
        - "traefik.http.routers.n8n_editor.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_editor.service=n8n_editor"
        - "traefik.http.services.n8n_editor.loadbalancer.server.port=5678"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 09.n8n-workers.yaml
    cat <<EOF > 09.n8n-workers.yaml
version: "3.7"
services:
  n8n_worker:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: worker --concurrency=10
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 10.n8n-webhooks.yaml
    cat <<EOF > 10.n8n-webhooks.yaml
version: "3.7"
services:
  n8n_webhook:
    image: n8nio/n8n:2.0.2
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    command: webhook
    networks:
      - network_swarm_public
    environment:
$N8N_ENV_BLOCK
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.swarm.network=network_swarm_public"
        - "traefik.http.routers.n8n_webhook.rule=Host(\`${N8N_WEBHOOK_DOMAIN}\`)"
        - "traefik.http.routers.n8n_webhook.entrypoints=websecure"
        - "traefik.http.routers.n8n_webhook.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.n8n_webhook.service=n8n_webhook"
        - "traefik.http.services.n8n_webhook.loadbalancer.server.port=5678"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 12.dify-pgvector.yaml
    cat <<EOF > 12.dify-pgvector.yaml
version: '3.7'

services:
  pgvector:
    image: pgvector/pgvector:pg16
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    environment:
      PGUSER: postgres
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
      POSTGRES_DB: dify
    volumes:
      - pgvector_data:/var/lib/postgresql/data
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "2"
          memory: 2048M

volumes:
  pgvector_data:
    external: true
    name: pgvector_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # DIFY CONFIGURATION
    if [ "$ENABLE_DIFY" = true ]; then
        DIFY_COMMON_ENV=$(cat <<ENV_BLOCK
      LOG_LEVEL: WARNING
      SECRET_KEY: ${DIFY_SECRET_KEY}
      INIT_PASSWORD: ''
      MIGRATION_ENABLED: 'true'
      DEPLOY_ENV: PRODUCTION
      ETL_TYPE: dify
      APP_WEB_URL: 'https://${DIFY_WEB_DOMAIN}'
      CONSOLE_WEB_URL: 'https://${DIFY_WEB_DOMAIN}'
      CONSOLE_API_URL: 'https://${DIFY_API_DOMAIN}'
      SERVICE_API_URL: 'https://${DIFY_API_DOMAIN}'
      APP_API_URL: 'https://${DIFY_API_DOMAIN}'
      FILES_URL: ''
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_USERNAME: ''
      REDIS_PASSWORD: '${REDIS_PASSWORD}'
      REDIS_USE_SSL: 'false'
      REDIS_DB: 0
      CELERY_BROKER_URL: redis://:${REDIS_PASSWORD}@redis:6379/3
      VECTOR_STORE: pgvector
      PGVECTOR_HOST: pgvector
      PGVECTOR_PORT: 5432
      PGVECTOR_USER: postgres
      PGVECTOR_PASSWORD: ${POSTGRES_PASSWORD}
      PGVECTOR_DATABASE: dify
      CODE_EXECUTION_ENDPOINT: "http://dify_sandbox:8194"
      CODE_EXECUTION_API_KEY: dify-sandbox
${DIFY_S3_BLOCK}
ENV_BLOCK
)

    # 13.dify-sandbox.yaml
    cat <<EOF > 13.dify-sandbox.yaml
version: "3.7"
services:
  dify_sandbox:
    image: langgenius/dify-sandbox:0.2.12
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    cap_add:
      - SYS_ADMIN
    environment:
      API_KEY: dify-sandbox
      GIN_MODE: release
      WORKER_TIMEOUT: 30
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 2048M

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 14.dify-web.yaml
    cat <<EOF > 14.dify-web.yaml
version: '3.7'
services:
  dify_web:
    image: langgenius/dify-web:1.11.1
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    environment:
      MODE: api
$DIFY_COMMON_ENV
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dify_web.rule=Host(\`${DIFY_WEB_DOMAIN}\`)"
        - "traefik.http.routers.dify_web.entrypoints=websecure"
        - "traefik.http.routers.dify_web.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.dify_web.service=dify_web"
        - "traefik.http.services.dify_web.loadbalancer.server.port=3000"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 15.dify-api.yaml
    cat <<EOF > 15.dify-api.yaml
version: '3.7'
services:
  dify_api:
    image: langgenius/dify-api:1.11.1
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    environment:
      MODE: api
$DIFY_COMMON_ENV
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.dify_api.rule=Host(\`${DIFY_API_DOMAIN}\`)"
        - "traefik.http.routers.dify_api.entrypoints=websecure"
        - "traefik.http.routers.dify_api.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.dify_api.service=dify_api"
        - "traefik.http.services.dify_api.loadbalancer.server.port=5001"

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    # 16.dify-worker.yaml
    cat <<EOF > 16.dify-worker.yaml
version: '3.7'
services:
  dify_worker:
    image: langgenius/dify-api:1.11.1
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    environment:
      MODE: worker
$DIFY_COMMON_ENV
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
    fi

    # 17.evolution_v2.yaml
    cat <<EOF > 17.evolution_v2.yaml
version: "3.7"

services:
  evolution_v2:
    image: atendai/evolution-api:v2.3.7
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    volumes:
      - evolution_instances:/evolution/instances
    networks:
      - network_swarm_public
    environment:
      - SERVER_URL=https://${EVOLUTION_DOMAIN}
      - DEL_INSTANCE=false
      - CONFIG_SESSION_PHONE_CLIENT=Windows
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1015901307
      - QRCODE_LIMIT=30
      - LANGUAGE=pt-BR
      - AUTHENTICATION_API_KEY=${EVOLUTION_API_KEY}
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - DATABASE_ENABLED=true
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/evolution
      - DATABASE_CONNECTION_CLIENT_NAME=evolution_v2
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_DATA_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - DATABASE_SAVE_DATA_LABELS=true
      - DATABASE_SAVE_DATA_HISTORIC=true
      - RABBITMQ_ENABLED=true
      - RABBITMQ_URI=amqp://${RABBITMQ_USER}:${RABBITMQ_PASSWORD}@rabbitmq:5672/
      - RABBITMQ_EXCHANGE_NAME=evolution_v2
      - RABBITMQ_GLOBAL_ENABLED=true
      - WEBSOCKET_ENABLED=false
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v20.0
      - WA_BUSINESS_LANGUAGE=pt_BR
      - WEBHOOK_GLOBAL_ENABLED=false
      - TYPEBOT_ENABLED=true
      - TYPEBOT_API_VERSION=latest
      - TYPEBOT_KEEP_OPEN=false
      - TYPEBOT_SEND_MEDIA_BASE64=true
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://postgres:${POSTGRES_PASSWORD}@postgres:5432/chatwoot?sslmode=disable
      - CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true
      - OPENAI_ENABLED=true
      - DIFY_ENABLED=true
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://:${REDIS_PASSWORD}@redis:6379/1
      - CACHE_REDIS_PREFIX_KEY=evolution_v2
      - CACHE_REDIS_SAVE_INSTANCES=true
      - CACHE_LOCAL_ENABLED=false
${EVO_S3_BLOCK}
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      resources:
        limits:
          cpus: "1"
          memory: 1024M
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.evolution_v2.rule=Host(\`${EVOLUTION_DOMAIN}\`)"
        - "traefik.http.routers.evolution_v2.entrypoints=websecure"
        - "traefik.http.routers.evolution_v2.tls.certresolver=letsencryptresolver"
        - "traefik.http.routers.evolution_v2.priority=1"
        - "traefik.http.routers.evolution_v2.service=evolution_v2"
        - "traefik.http.services.evolution_v2.loadbalancer.server.port=8080"
        - "traefik.http.services.evolution_v2.loadbalancer.passHostHeader=true"

volumes:
  evolution_instances:
    external: true
    name: evolution_v2_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

    print_success "Arquivos YAML gerados com sucesso!"

    # Passo 2 (Execução): Iniciar Serviços
    print_step "INICIANDO SERVIÇOS DE INFRAESTRUTURA"
    
    # 1. Traefik e Portainer
    docker stack deploy -c 04.traefik.yaml traefik
    docker stack deploy -c 05.portainer.yaml portainer
    
    print_info "Aguardando serviços de infraestrutura subirem (15s)..."
    sleep 15
    
    # 2. Bancos de Dados
    docker stack deploy -c 06.postgres.yaml postgres
    docker stack deploy -c 07.redis.yaml redis
    docker stack deploy -c 11.rabbitmq.yaml rabbitmq
    
    print_info "Aguardando bancos de dados e RabbitMQ inicializarem (30s)..."
    sleep 30

    # 3. Criação do Banco N8N
    print_step "CONFIGURANDO BANCO DE DADOS N8N"
    print_info "Tentando conectar ao Postgres para criar o banco 'n8n'..."
    
    # Loop para encontrar o container ID do postgres (pode demorar um pouco no swarm)
    POSTGRES_CONTAINER=""
    for i in {1..10}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$POSTGRES_CONTAINER" ]; then
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE n8n;" >/dev/null 2>&1; then
            print_success "Banco de dados 'n8n' criado com sucesso!"
        else
            print_warning "Banco de dados 'n8n' já existe ou erro na criação (verifique logs)."
        fi
        
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE evolution;" >/dev/null 2>&1; then
            print_success "Banco de dados 'evolution' criado com sucesso!"
        else
            print_warning "Banco de dados 'evolution' já existe ou erro na criação (verifique logs)."
        fi

        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE chatwoot;" >/dev/null 2>&1; then
            print_success "Banco de dados 'chatwoot' criado com sucesso!"
        else
            print_warning "Banco de dados 'chatwoot' já existe ou erro na criação (verifique logs)."
        fi

        if [ "$ENABLE_DIFY" = true ]; then
            if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE dify;" >/dev/null 2>&1; then
                print_success "Banco de dados 'dify' criado com sucesso!"
            else
                print_warning "Banco de dados 'dify' já existe ou erro na criação (verifique logs)."
            fi
        fi
    else
        print_error "Não foi possível encontrar o container do Postgres. Crie os bancos 'n8n', 'evolution' e 'chatwoot' manualmente depois."
    fi

    # 4. Deploy Aplicações
    print_step "DEPLOY DAS APLICAÇÕES DE NEGÓCIO"
    
    # Criar volume externo para Evolution
    docker volume create evolution_v2_data >/dev/null
    
    docker stack deploy -c 08.n8n-editor.yaml n8n_editor
    docker stack deploy -c 09.n8n-workers.yaml n8n_worker
    docker stack deploy -c 10.n8n-webhooks.yaml n8n_webhook
    docker stack deploy -c 17.evolution_v2.yaml evolution_v2

    if [ "$ENABLE_DIFY" = true ]; then
        print_info "Realizando deploy do Dify AI..."
        # Criar volumes externos para Dify se necessário
        docker volume create pgvector_data >/dev/null

        # 1. Deploy PGVector e Sandbox (Dependências)
        docker stack deploy -c 12.dify-pgvector.yaml dify_pgvector
        docker stack deploy -c 13.dify-sandbox.yaml dify_sandbox
        
        # 2. Deploy API (Migration)
        print_info "Iniciando Dify API (Migrações de Banco de Dados)..."
        docker stack deploy -c 15.dify-api.yaml dify_api
        print_info "Aguardando migrações do Dify API (45s)..."
        sleep 45

        # 3. Deploy Web e Worker
        docker stack deploy -c 14.dify-web.yaml dify_web
        docker stack deploy -c 16.dify-worker.yaml dify_worker
    fi
    
    # Resumo Final
    print_step "SETUP CONCLUÍDO!"
    if [ "$IS_AWS" = true ]; then
        echo -e "${GREEN}✅ Infraestrutura AWS (Swarm) implantada!${RESET}"
    else
        echo -e "${GREEN}✅ Infraestrutura Google Cloud (Swarm) implantada!${RESET}"
    fi
    echo ""
    echo -e "${BOLD}${CYAN}Acesse seus serviços:${RESET}"
    echo -e "   ${ARROW} Portainer: https://${PORTAINER_DOMAIN}"
    echo -e "   ${ARROW} N8N Editor: https://${N8N_EDITOR_DOMAIN}"
    echo -e "   ${ARROW} N8N Webhook: https://${N8N_WEBHOOK_DOMAIN}"
    echo -e "   ${ARROW} RabbitMQ Panel: https://${RABBITMQ_DOMAIN}"
    echo -e "   ${ARROW} Evolution API: https://${EVOLUTION_DOMAIN}"
    echo -e "   ${ARROW} Evolution Docs: https://${EVOLUTION_DOMAIN}/docs"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${ARROW} Dify Web: https://${DIFY_WEB_DOMAIN}"
        echo -e "   ${ARROW} Dify API: https://${DIFY_API_DOMAIN}"
    fi

    echo ""
    echo -e "${YELLOW}⚠️  Configure sua senha de administrador no Portainer imediatamente!${RESET}"
    echo -e "   Link direto: https://${PORTAINER_DOMAIN}/#/init/admin"
    echo ""
    echo -e "${BOLD}${MAGENTA}🔒 CREDENCIAIS GERADAS (SALVE AGORA!):${RESET}"
    echo -e "   ${WHITE}Postgres Password:${RESET} ${POSTGRES_PASSWORD}"
    echo -e "   ${WHITE}Redis Password:${RESET} ${REDIS_PASSWORD}"
    echo -e "   ${WHITE}RabbitMQ User/Pass:${RESET} ${RABBITMQ_USER} / ${RABBITMQ_PASSWORD}"
    echo -e "   ${WHITE}N8N Encryption Key:${RESET} ${N8N_ENCRYPTION_KEY}"
    echo -e "   ${WHITE}Evolution Global API Key:${RESET} ${EVOLUTION_API_KEY}"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${WHITE}Dify Secret Key:${RESET} ${DIFY_SECRET_KEY}"
    else
        echo -e "${DIM}Dify não foi instalado.${RESET}"
    fi
    echo ""
}

# ===== SETUP AWS (SWARM) =====
setup_aws() {
    print_step "INICIANDO SETUP AWS (DOCKER SWARM)"
    
    if [ "$EUID" -ne 0 ]; then 
       print_error "Execute com sudo ou como root"
       exit 1
    fi

    echo -e "${YELLOW}⚠️  Você escolheu o setup AWS (Swarm Architecture)${RESET}"
    read -p "$(echo -e ${BOLD}${GREEN}"Confirmar instalação AWS? (s/n): "${RESET})" CONFIRM_AWS
    if [[ ! "$CONFIRM_AWS" =~ ^(s|S|sim|SIM)$ ]]; then exit 0; fi

    IS_AWS=true

    read -p "$(echo -e ${CYAN}"🗝️  AWS_ACCESS_KEY_ID: "${RESET})" AWS_ACCESS_KEY_ID
    read -sp "$(echo -e ${CYAN}"🔒 AWS_SECRET_ACCESS_KEY: "${RESET})" AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "$(echo -e ${CYAN}"🌍 Região AWS (ex: us-east-1): "${RESET})" S3_REGION
    read -p "$(echo -e ${CYAN}"🪣 Nome do Bucket S3: "${RESET})" S3_BUCKET_NAME
    echo ""

    print_step "PREPARANDO AMBIENTE AWS"
    {
        apt update -y && apt upgrade -y
        apt install -y awscli unzip curl
    } > /tmp/aws_setup.log 2>&1 &
    spinner $!

    install_docker

    print_info "Configurando AWS CLI..."
    mkdir -p /root/.aws
    cat > /root/.aws/credentials <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
EOF
    cat > /root/.aws/config <<EOF
[default]
region = $S3_REGION
output = json
EOF

    setup_swarm_architecture
}

# ===== SETUP GCP (SWARM) =====
setup_gcp() {
    print_step "INICIANDO SETUP GOOGLE CLOUD (DOCKER SWARM)"
    
    if [ "$EUID" -ne 0 ]; then 
       print_error "Execute com sudo ou como root"
       exit 1
    fi

    print_step "PREPARANDO AMBIENTE GCP"
    {
        apt-get update && apt-get upgrade -y
        apt-get install -y git curl gnupg lsb-release
    } > /tmp/gcp_update.log 2>&1 &
    spinner $!

    install_docker

    setup_swarm_architecture
}

# ===== MENU PRINCIPAL =====
print_banner

echo -e "Selecione o tipo de infraestrutura:"
echo -e "  [1] ${YELLOW}AWS${RESET} (Single Node / Docker Swarm)"
echo -e "  [2] ${BLUE}Google Cloud${RESET} (Multi Node / Docker Swarm)"
echo ""
read -p "Opção (1 ou 2): " CLOUD_OPTION

case $CLOUD_OPTION in
    1)
        setup_aws
        ;;
    2)
        setup_gcp
        ;;
    *)
        print_error "Opção inválida!"
        exit 1
        ;;
esac
