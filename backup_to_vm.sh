#!/bin/bash
set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${GREEN}=== Backup Local na VM ===${RESET}"

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker não encontrado. Este script requer Docker.${RESET}"
    exit 1
fi

# Variáveis de Configuração
BACKUP_ROOT_DIR="${BACKUP_ROOT_DIR:-/opt/infra/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TEMP_DIR="/tmp/backup_vm_temp"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="backup_${TIMESTAMP}.tar.gz"

echo -e "${YELLOW}Diretório de destino: $BACKUP_ROOT_DIR${RESET}"
echo -e "${YELLOW}Retenção: $RETENTION_DAYS dias${RESET}"

# Preparar diretórios
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR"
mkdir -p "$BACKUP_ROOT_DIR"

# 1. Dump do Banco de Dados (Postgres Principal)
POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
if [ -n "$POSTGRES_CONTAINER" ]; then
    echo -e "Realizando Dump do Postgres (Main)..."
    docker exec "$POSTGRES_CONTAINER" pg_dumpall -U postgres > "$TEMP_DIR/postgres_dump.sql"
else
    echo -e "${YELLOW}Aviso: Container Postgres não encontrado. Pulando dump de banco.${RESET}"
fi

# 1.1 Dump do Banco de Dados (Dify PgVector)
PGVECTOR_CONTAINER=$(docker ps -q -f name=pgvector)
if [ -z "$PGVECTOR_CONTAINER" ]; then PGVECTOR_CONTAINER=$(docker ps -q -f name=dify_pgvector); fi

if [ -n "$PGVECTOR_CONTAINER" ]; then
    echo -e "Realizando Dump do PgVector (Dify)..."
    docker exec "$PGVECTOR_CONTAINER" pg_dumpall -U postgres > "$TEMP_DIR/dify_pgvector_dump.sql"
else
    echo -e "${YELLOW}Aviso: Container PgVector não encontrado. Pulando dump do Dify Vector Store.${RESET}"
fi

# 2. Backup de Volumes Importantes
echo -e "Copiando volumes..."
mkdir -p "$TEMP_DIR/volumes"

backup_volume() {
    local VOL_PATH="/var/lib/docker/volumes/$1/_data"
    local DEST_NAME="$2"
    if [ -d "$VOL_PATH" ]; then
        echo "  - Copiando $1..."
        cp -r "$VOL_PATH" "$TEMP_DIR/volumes/$DEST_NAME"
    else
        echo "  - Volume $1 não encontrado (ignorando)."
    fi
}

backup_volume "evolution_v2_data" "evolution_instances"
backup_volume "portainer_data" "portainer_data"
backup_volume "volume_swarm_certificates" "traefik_certs"
backup_volume "n8n_data" "n8n_data"
backup_volume "dify_storage" "dify_storage"

# 3. Compactação e Movimentação
echo -e "Compactando arquivos para $BACKUP_ROOT_DIR/$FILENAME..."
tar -czf "$BACKUP_ROOT_DIR/$FILENAME" -C "$TEMP_DIR" .
rm -rf "$TEMP_DIR"

if [ -f "$BACKUP_ROOT_DIR/$FILENAME" ]; then
    echo -e "${GREEN}✅ Backup salvo com sucesso em: $BACKUP_ROOT_DIR/$FILENAME${RESET}"
    
    # 4. Rotação de Backups (Remover antigos)
    echo -e "${YELLOW}Verificando rotação de backups (mais antigos que $RETENTION_DAYS dias)...${RESET}"
    find "$BACKUP_ROOT_DIR" -name "backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -exec rm {} \; -exec echo "  - Removido: {}" \;
else
    echo -e "${RED}❌ Falha ao criar arquivo de backup.${RESET}"
    exit 1
fi
