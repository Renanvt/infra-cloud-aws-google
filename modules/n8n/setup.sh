#!/bin/bash

setup_n8n_vars() {
    confirm_input "${CYAN}🌐 Domínio N8N Editor (ex: editor.meudominio.com): ${RESET}" "N8N Editor será:" N8N_EDITOR_DOMAIN
    confirm_input "${CYAN}🌐 Domínio N8N Webhook (ex: webhook.meudominio.com): ${RESET}" "N8N Webhook será:" N8N_WEBHOOK_DOMAIN
    confirm_input "${CYAN}🔑 Chave de Encriptação N8N: ${RESET}" "N8N Key:" N8N_ENCRYPTION_KEY
}

generate_n8n_yamls() {
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
      resources:
        limits:
          cpus: "${N8N_LIMIT_CPU}"
          memory: ${N8N_LIMIT_RAM}
        reservations:
          cpus: "${N8N_REQ_CPU}"
          memory: ${N8N_REQ_RAM}
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
      resources:
        limits:
          cpus: "${N8N_LIMIT_CPU}"
          memory: ${N8N_LIMIT_RAM}
        reservations:
          cpus: "${N8N_REQ_CPU}"
          memory: ${N8N_REQ_RAM}

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
}
