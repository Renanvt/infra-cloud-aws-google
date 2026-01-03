#!/bin/bash

setup_evolution_vars() {
    confirm_input "${CYAN} Domínio Evolution API (ex: api.meudominio.com): ${RESET}" "Evolution API será:" EVOLUTION_DOMAIN
    confirm_input "${CYAN}🔑 API Key Global (Evolution): ${RESET}" "Evolution Key:" EVOLUTION_API_KEY

    # Evolution S3
    echo -e ""
    read -p "$(echo -e ${CYAN}"Deseja habilitar S3 para Evolution API? (s/n): "${RESET})" ENABLE_S3 < /dev/tty || true
    if [[ "$ENABLE_S3" =~ ^(s|S|sim|SIM)$ ]]; then
        EVO_ENABLE_S3=true
        confirm_input "${CYAN}🪣 Nome do Bucket S3 (Evolution): ${RESET}" "Bucket:" EVO_S3_BUCKET
        confirm_input "${CYAN}🌍 Região S3 (ex: us-east-1): ${RESET}" "Região:" EVO_S3_REGION
        confirm_input "${CYAN}🔗 Endpoint S3 (ex: s3.us-east-1.amazonaws.com): ${RESET}" "Endpoint:" EVO_S3_ENDPOINT
        confirm_input "${CYAN}🗝️ Access Key: ${RESET}" "Access Key:" EVO_S3_ACCESS_KEY
        confirm_input "${CYAN} 🔒 Secret Access Key: ${RESET}" "Secret Key:" EVO_S3_SECRET_KEY
        
        # Correção de Endpoint (Remover protocolo para MinIO client)
        EVO_S3_ENDPOINT=${EVO_S3_ENDPOINT#https://}
        EVO_S3_ENDPOINT=${EVO_S3_ENDPOINT#http://}

        # Correção de Região (Remover s3. e .amazonaws.com se o usuário colar o endpoint)
        if [[ "$EVO_S3_REGION" =~ s3\.([a-z0-9-]+)\.amazonaws\.com ]]; then
             EVO_S3_REGION="${BASH_REMATCH[1]}"
             print_warning "Região corrigida para: $EVO_S3_REGION"
        fi

        EVO_S3_BLOCK="      - S3_ENABLED=true
      - S3_ACCESS_KEY=${EVO_S3_ACCESS_KEY}
      - S3_SECRET_KEY=${EVO_S3_SECRET_KEY}
      - S3_BUCKET=${EVO_S3_BUCKET}
      - S3_PORT=443
      - S3_REGION=${EVO_S3_REGION}
      - S3_ENDPOINT=${EVO_S3_ENDPOINT}
      - S3_USE_SSL=true"
    else
        EVO_S3_BLOCK="      - S3_ENABLED=false"
    fi
}

generate_evolution_yaml() {
    # 18.evolution_v2.yaml
    cat <<EOF > 18.evolution_v2.yaml
version: "3.7"

services:
  evolution_v2:
    image: atendai/evolution-api:v2.2.3
    volumes:
      - evolution_instances:/evolution/instances
    networks:
      - network_swarm_public
    environment:
      - SERVER_URL=https://${EVOLUTION_DOMAIN}
      - DEL_INSTANCE=false
      - CONFIG_SESSION_PHONE_CLIENT=Windows
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1030831524
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
          cpus: "${EVO_LIMIT_CPU}"
          memory: ${EVO_LIMIT_RAM}
        reservations:
          cpus: "${EVO_REQ_CPU}"
          memory: ${EVO_REQ_RAM}
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
}
