#!/bin/bash
set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${GREEN}=== Backup para S3 ===${RESET}"

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker não encontrado. Este script requer Docker.${RESET}"
    exit 1
fi

# Variáveis de Configuração (Pode ser alterado ou passado via ENV)
BACKUP_DIR="/tmp/backup_s3_temp"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="backup_${TIMESTAMP}.tar.gz"

# Validação de BUSINESS_NAME (Letras minúsculas e números, tudo junto)
if [ -z "$BUSINESS_NAME" ]; then
    while true; do
        read -p "💼 Nome do Negócio (ex: alobexpress): " INPUT_BUSINESS
        if [[ "$INPUT_BUSINESS" =~ ^[a-z0-9]+$ ]]; then
            BUSINESS_NAME="$INPUT_BUSINESS"
            break
        else
            echo -e "${RED}Erro: Digite apenas letras minúsculas e números, sem espaços.${RESET}"
        fi
    done
fi

# Validação de CLOUD_PROVIDER (Máximo 7 letras, tudo junto)
if [ -z "$CLOUD_PROVIDER" ]; then
    while true; do
        read -p "☁️  Sua Cloud (ex: aws, gcp): " INPUT_CLOUD
        if [[ "$INPUT_CLOUD" =~ ^[a-zA-Z]{1,7}$ ]]; then
            CLOUD_PROVIDER="$INPUT_CLOUD"
            break
        else
            echo -e "${RED}Erro: Digite apenas letras (máximo 7), sem espaços.${RESET}"
        fi
    done
fi

# Validação de INSTANCE_NAME (Letras minúsculas, números e hífens, max 30)
if [ -z "$INSTANCE_NAME" ]; then
    while true; do
        read -p "🖥️  Sua VM (ex: vm-production-01): " INPUT_VM
        if [[ "$INPUT_VM" =~ ^[a-z0-9-]{1,30}$ ]]; then
            INSTANCE_NAME="$INPUT_VM"
            break
        else
            echo -e "${RED}Erro: Digite apenas letras minúsculas, números ou hífens (máximo 30).${RESET}"
        fi
    done
fi

if [ -z "$BUSINESS_NAME" ]; then BUSINESS_NAME="unnamed"; fi
if [ -z "$CLOUD_PROVIDER" ]; then CLOUD_PROVIDER="unknown"; fi
if [ -z "$INSTANCE_NAME" ]; then INSTANCE_NAME="vm"; fi

TARGET_S3_FOLDER="backups/${BUSINESS_NAME}_${CLOUD_PROVIDER}_${INSTANCE_NAME}"

# Solicitar Credenciais S3 se não estiverem no ambiente
if [ -z "$S3_BUCKET" ]; then read -p "Nome do Bucket S3: " S3_BUCKET; fi
if [ -z "$S3_REGION" ]; then read -p "Região S3 (ex: us-east-1): " S3_REGION; fi

# Sanitização da Região (Remove s3., .amazonaws.com e trata east-1)
S3_REGION=$(echo "$S3_REGION" | sed -E 's/^(https?:\/\/)?(s3\.)?//' | sed -E 's/\.amazonaws\.com$//')
if [[ "$S3_REGION" == "east-1" ]]; then S3_REGION="us-east-1"; fi

if [ -z "$S3_ACCESS_KEY" ]; then read -p "AWS Access Key ID: " S3_ACCESS_KEY; fi
if [ -z "$S3_SECRET_KEY" ]; then read -s -p "AWS Secret Access Key: " S3_SECRET_KEY; echo ""; fi

# Preparar diretório temporário
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR/backup_content"
TARGET_DIR="$BACKUP_DIR/backup_content"
echo -e "${YELLOW}Diretório temporário criado: $TARGET_DIR${RESET}"

# 1. Dump do Banco de Dados (Postgres Principal)
POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
if [ -n "$POSTGRES_CONTAINER" ]; then
    echo -e "Realizando Dump do Postgres (Main)..."
    docker exec "$POSTGRES_CONTAINER" pg_dumpall -U postgres > "$TARGET_DIR/postgres_dump.sql"
else
    echo -e "${YELLOW}Aviso: Container Postgres não encontrado. Pulando dump de banco.${RESET}"
fi

# 1.1 Dump do Banco de Dados (Dify PgVector)
PGVECTOR_CONTAINER=$(docker ps -q -f name=pgvector)
if [ -z "$PGVECTOR_CONTAINER" ]; then PGVECTOR_CONTAINER=$(docker ps -q -f name=dify_pgvector); fi

if [ -n "$PGVECTOR_CONTAINER" ]; then
    echo -e "Realizando Dump do PgVector (Dify)..."
    docker exec "$PGVECTOR_CONTAINER" pg_dumpall -U postgres > "$TARGET_DIR/dify_pgvector_dump.sql"
else
    echo -e "${YELLOW}Aviso: Container PgVector não encontrado. Pulando dump do Dify Vector Store.${RESET}"
fi

# 2. Backup de Volumes Importantes
echo -e "Copiando volumes..."
mkdir -p "$TARGET_DIR/volumes"

backup_volume() {
    local VOL_PATH="/var/lib/docker/volumes/$1/_data"
    local DEST_NAME="$2"
    if [ -d "$VOL_PATH" ]; then
        echo "  - Copiando $1..."
        cp -r "$VOL_PATH" "$TARGET_DIR/volumes/$DEST_NAME"
    else
        echo "  - Volume $1 não encontrado (ignorando)."
    fi
}

backup_volume "evolution_v2_data" "evolution_instances"
backup_volume "portainer_data" "portainer_data"
backup_volume "volume_swarm_certificates" "traefik_certs"
backup_volume "dify_plugin_cwd" "dify_plugins"

# 3. Compactação
echo -e "Compactando arquivos em $FILENAME..."
# Compactar a pasta backup_content para manter a estrutura
tar -czf "$FILENAME" -C "$BACKUP_DIR" backup_content
rm -rf "$BACKUP_DIR"

# 4. Upload para S3
echo -e "${YELLOW}Enviando para S3 ($S3_BUCKET/$TARGET_S3_FOLDER/$FILENAME)...${RESET}"

AWS_CMD="s3 cp /backup/$FILENAME s3://$S3_BUCKET/$TARGET_S3_FOLDER/$FILENAME --region $S3_REGION"
if [ -n "$S3_ENDPOINT" ]; then AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"; fi

docker run --rm \
    -v "$(pwd)/$FILENAME:/backup/$FILENAME" \
    -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" \
    -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
    amazon/aws-cli $AWS_CMD

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Backup enviado com sucesso para o S3!${RESET}"
    rm -f "$FILENAME"
else
    echo -e "${RED}❌ Erro ao enviar para o S3. O arquivo local $FILENAME foi mantido.${RESET}"
    exit 1
fi
