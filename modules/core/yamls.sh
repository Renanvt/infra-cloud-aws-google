#!/bin/bash

generate_core_yamls() {
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
      resources:
        limits:
          cpus: "${TRAEFIK_LIMIT_CPU}"
          memory: ${TRAEFIK_LIMIT_RAM}
        reservations:
          cpus: "${TRAEFIK_REQ_CPU}"
          memory: ${TRAEFIK_REQ_RAM}
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.api.rule=Host(\`traefik.local\`)"
        - "traefik.http.routers.api.service=api@internal"
        - "traefik.http.services.traefik.loadbalancer.server.port=8080"
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
          cpus: "${POSTGRES_LIMIT_CPU}"
          memory: ${POSTGRES_LIMIT_RAM}
        reservations:
          cpus: "${POSTGRES_REQ_CPU}"
          memory: ${POSTGRES_REQ_RAM}

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
          cpus: "${REDIS_LIMIT_CPU}"
          memory: ${REDIS_LIMIT_RAM}
        reservations:
          cpus: "${REDIS_REQ_CPU}"
          memory: ${REDIS_REQ_RAM}

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
          cpus: "${RABBITMQ_LIMIT_CPU}"
          memory: ${RABBITMQ_LIMIT_RAM}
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
}
