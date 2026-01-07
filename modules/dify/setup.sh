#!/bin/bash

setup_dify_vars() {
    print_step "CONFIGURAÇÃO DIFY AI"
    echo -e "   ${YELLOW}O Dify requer MÍNIMO de 2 vCPU e 2GB RAM adicionais.${RESET}"
    echo -e "   ${YELLOW}Considerando N8N, Evolution, Postgres, Redis e RabbitMQ, sua VM deve ter:${RESET}"
    echo -e "   ${BOLD}➜ Recomendado: 4 vCPU e 8GB RAM (ou mais)${RESET}"
    echo -e "   ${DIM}Se sua VM tiver menos recursos, os serviços podem falhar ou travar.${RESET}"
    
    # Check de requisitos
    if (( $(echo "$TOTAL_RAM_MB < 3800" | bc -l) )); then
        print_warning "Sua VM tem apenas ${TOTAL_RAM_MB}MB RAM. Dify pode ficar instável."
        read -p "Deseja continuar mesmo assim? (s/n): " FORCE_DIFY < /dev/tty || true
        if [[ ! "$FORCE_DIFY" =~ ^(s|S|sim|SIM)$ ]]; then
            ENABLE_DIFY=false
        else
            ENABLE_DIFY=true
        fi
    else
        echo -e "${GREEN}✅ Sua VM (${TOTAL_RAM_MB}MB RAM / ${TOTAL_CPU_CORES} vCPU) suporta o Dify perfeitamente.${RESET}"
        read -p "Deseja instalar o Dify AI? (s/n): " INSTALL_DIFY_OPT < /dev/tty || true
        if [[ "$INSTALL_DIFY_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
            ENABLE_DIFY=true
        else
            ENABLE_DIFY=false
        fi
    fi

    if [ "$ENABLE_DIFY" = true ]; then
        confirm_input "${CYAN} Domínio Dify Web (ex: dify.meudominio.com): ${RESET}" "Dify Web:" DIFY_WEB_DOMAIN
        confirm_input "${CYAN} Domínio Dify API (ex: api-dify.meudominio.com): ${RESET}" "Dify API:" DIFY_API_DOMAIN
        confirm_input "${CYAN}🔒 Dify Secret Key (Gere uma forte): ${RESET}" "Dify Secret:" DIFY_SECRET_KEY

        DIFY_COOKIE_DOMAIN=$(echo "$DIFY_WEB_DOMAIN" | awk -F. '{ if ($NF=="br" && $(NF-1) ~ /^(com|net|org|gov|edu)$/) print $(NF-2)"."$(NF-1)"."$NF; else print $(NF-1)"."$NF }')
        DIFY_INNER_API_KEY="sk-$(openssl rand -hex 20)"
        DIFY_PLUGIN_DAEMON_KEY="${DIFY_INNER_API_KEY}"

        # Reutilizar S3 do Evolution?
        if [ "$EVO_ENABLE_S3" = true ]; then
             echo -e "${CYAN}Detectamos configuração S3 no Evolution (Bucket: $EVO_S3_BUCKET).${RESET}"
             read -p "Deseja reutilizar estas credenciais para o Dify? (s/n): " REUSE_S3 < /dev/tty || true
             if [[ "$REUSE_S3" =~ ^(s|S|sim|SIM)$ ]]; then
                 DIFY_S3_BUCKET="$EVO_S3_BUCKET"
                 DIFY_S3_REGION="$EVO_S3_REGION"
                 DIFY_S3_ENDPOINT="$EVO_S3_ENDPOINT"
                 DIFY_S3_ACCESS_KEY="$EVO_S3_ACCESS_KEY"
                 DIFY_S3_SECRET_KEY="$EVO_S3_SECRET_KEY"
                 DIFY_ENABLE_S3=true
             else
                 # Pergunta manual S3 Dify
                 read -p "Deseja configurar S3 diferente para Dify? (s/n): " ENABLE_DIFY_S3_OPT < /dev/tty || true
                 if [[ "$ENABLE_DIFY_S3_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
                    DIFY_ENABLE_S3=true
                    confirm_input "${CYAN}🪣 Nome do Bucket S3 (Dify): ${RESET}" "Bucket:" DIFY_S3_BUCKET
                    confirm_input "${CYAN}🌍 Região S3: ${RESET}" "Região:" DIFY_S3_REGION
                    confirm_input "${CYAN}🔗 Endpoint S3 (ex: https://...): ${RESET}" "Endpoint:" DIFY_S3_ENDPOINT
                    confirm_input "${CYAN}🗝️ Access Key: ${RESET}" "Access Key:" DIFY_S3_ACCESS_KEY
                    confirm_input "${CYAN} 🔒 Secret Access Key: ${RESET}" "Secret Key:" DIFY_S3_SECRET_KEY
                 else
                    DIFY_ENABLE_S3=false
                 fi
             fi
        else
             # Evolution sem S3, pergunta normal pro Dify
             read -p "Deseja configurar S3 para Dify? (s/n): " ENABLE_DIFY_S3_OPT < /dev/tty || true
             if [[ "$ENABLE_DIFY_S3_OPT" =~ ^(s|S|sim|SIM)$ ]]; then
                DIFY_ENABLE_S3=true
                confirm_input "${CYAN}🪣 Nome do Bucket S3 (Dify): ${RESET}" "Bucket:" DIFY_S3_BUCKET
                confirm_input "${CYAN}🌍 Região S3: ${RESET}" "Região:" DIFY_S3_REGION
                confirm_input "${CYAN}🔗 Endpoint S3 (ex: https://...): ${RESET}" "Endpoint:" DIFY_S3_ENDPOINT
                confirm_input "${CYAN}🗝️ Access Key ID: ${RESET}" "Access Key:" DIFY_S3_ACCESS_KEY
                confirm_input "${CYAN} 🔒 Secret Access Key: ${RESET}" "Secret Key:" DIFY_S3_SECRET_KEY
             else
                DIFY_ENABLE_S3=false
             fi
        fi

        # Correção HTTPS Dify e Configurações S3
        if [ "$DIFY_ENABLE_S3" = true ]; then
            # Forçar endpoint e region para AWS padrão se não especificado corretamente ou se for AWS
            if [[ "$DIFY_S3_ENDPOINT" == *"amazonaws.com"* ]] || [[ -z "$DIFY_S3_ENDPOINT" ]]; then
                DIFY_S3_ENDPOINT="https://s3.amazonaws.com"
                # Limpar região se tiver s3. ou .amazonaws.com
                DIFY_S3_REGION=$(echo "$DIFY_S3_REGION" | sed -E 's/^(https?:\/\/)?(s3\.)?//' | sed -E 's/\.amazonaws\.com$//')
            else
                 # Adicionar https se faltar para outros providers
                 if [[ ! "$DIFY_S3_ENDPOINT" =~ ^https:// ]]; then
                     DIFY_S3_ENDPOINT="https://${DIFY_S3_ENDPOINT}"
                 fi
            fi

             DIFY_S3_BLOCK=$(cat <<S3_BLOCK
      STORAGE_TYPE: s3
      S3_ENDPOINT: '${DIFY_S3_ENDPOINT}'
      S3_BUCKET_NAME: '${DIFY_S3_BUCKET}'
      S3_ACCESS_KEY: '${DIFY_S3_ACCESS_KEY}'
      S3_SECRET_KEY: '${DIFY_S3_SECRET_KEY}'
      S3_REGION: '${DIFY_S3_REGION}'
      S3_USE_SSL: 'true'
      S3_ADDRESSING_STYLE: 'virtual'
S3_BLOCK
)
        else
             DIFY_S3_BLOCK=$(cat <<S3_BLOCK
      STORAGE_TYPE: local
S3_BLOCK
)
        fi
    fi
}

generate_dify_yamls() {
    if [ "$ENABLE_DIFY" = true ]; then
        DIFY_COMMON_ENV=$(cat <<ENV_BLOCK
      LOG_LEVEL: WARNING
      SECRET_KEY: ${DIFY_SECRET_KEY}
      INIT_PASSWORD: ''
      MIGRATION_ENABLED: 'true'
      DEPLOY_ENV: PRODUCTION
      ETL_TYPE: dify
      # Segurança
      HTTP_REQUEST_MAX_CONNECT_TIMEOUT: 300
      HTTP_REQUEST_MAX_READ_TIMEOUT: 600
      HTTP_REQUEST_MAX_WRITE_TIMEOUT: 600
      # Performance
      INDEXING_MAX_SEGMENTATION_TOKENS_LENGTH: 1000
      CELERY_WORKER_MAX_TASKS_PER_CHILD: 200
      APP_WEB_URL: 'https://${DIFY_WEB_DOMAIN}'
      CONSOLE_WEB_URL: 'https://${DIFY_WEB_DOMAIN}'
      CONSOLE_API_URL: 'https://${DIFY_API_DOMAIN}'
      SERVICE_API_URL: 'https://${DIFY_API_DOMAIN}'
      APP_API_URL: 'https://${DIFY_API_DOMAIN}'
      FILES_URL: 'https://${DIFY_API_DOMAIN}/files'
      COOKIE_DOMAIN: '${DIFY_COOKIE_DOMAIN}'
      NEXT_PUBLIC_COOKIE_DOMAIN: '1'
      MARKETPLACE_ENABLED: 'true'
      MARKETPLACE_URL: 'https://marketplace.dify.ai'
      MARKETPLACE_API_URL: 'https://marketplace.dify.ai'
      PLUGIN_DAEMON_URL: 'http://dify_plugin_daemon_dify_plugin_daemon:5002'
      PLUGIN_DAEMON_KEY: ${DIFY_INNER_API_KEY}
      DIFY_INNER_API_KEY: '${DIFY_INNER_API_KEY}'
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
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
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
          cpus: "${DIFY_LIMIT_CPU}"
          memory: ${DIFY_LIMIT_RAM}
        reservations:
          cpus: "${DIFY_REQ_CPU}"
          memory: ${DIFY_REQ_RAM}

volumes:
  pgvector_data:
    external: true
    name: pgvector_data

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF

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
          cpus: "${DIFY_LIMIT_CPU}"
          memory: ${DIFY_LIMIT_RAM}
        reservations:
          cpus: "${DIFY_REQ_CPU}"
          memory: ${DIFY_REQ_RAM}

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
    networks:
      - network_swarm_public
    environment:
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
        - "traefik.http.services.dify_web.loadbalancer.passHostHeader=true"

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
    networks:
      - network_swarm_public
    environment:
      MODE: api
$DIFY_COMMON_ENV
      # Rate Limiting
      API_RATE_LIMIT_ENABLED: 'true'      # Ativa limite de requisições
      API_RATE_LIMIT: 60      # 60 requisições por minuto
      API_RATE_LIMIT_UI_ENABLED: 'true'      # Ativa limite de requisições na interface 
      API_RATE_LIMIT_UI: 60         # 60 requisições por minuto na UI
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
        - "traefik.http.services.dify_api.loadbalancer.passHostHeader=true"

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

    cat <<EOF > 17.dify-plugindaemon.yaml
version: '3.7'

services:
  dify_plugin_daemon:
    image: langgenius/dify-plugin-daemon:0.5.2-local
    hostname: "{{.Service.Name}}.{{.Task.Slot}}"
    networks:
      - network_swarm_public
    environment:
      DB_USERNAME: postgres
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      DB_HOST: postgres
      DB_PORT: 5432
      DB_DATABASE: dify
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_USERNAME: ''
      REDIS_PASSWORD: '${REDIS_PASSWORD}'
      REDIS_DB: 0
      SERVER_KEY: ${DIFY_PLUGIN_DAEMON_KEY}
      DIFY_INNER_API_URL: http://dify_api_dify_api:5001
      DIFY_INNER_API_KEY: ${DIFY_PLUGIN_DAEMON_KEY}
      PLUGIN_DIFY_INNER_API_URL: http://dify_api_dify_api:5001
      PLUGIN_DIFY_INNER_API_KEY: ${DIFY_PLUGIN_DAEMON_KEY}
      PLUGIN_REMOTE_INSTALLING_HOST: '0.0.0.0'
      PLUGIN_REMOTE_INSTALLING_PORT: '5003'
      PLUGIN_WORKING_PATH: /app/storage/cwd
      MARKETPLACE_ENABLED: 'true'
      MARKETPLACE_API_URL: https://marketplace.dify.ai
      FORCE_VERIFYING_SIGNATURE: 'true'
      ENFORCE_LANGGENIUS_PLUGIN_SIGNATURES: 'true'
    volumes:
      - dify_plugin_cwd:/app/storage/cwd
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager

volumes:
  dify_plugin_cwd:
    external: true
    name: dify_plugin_cwd

networks:
  network_swarm_public:
    external: true
    name: network_swarm_public
EOF
    fi
}
