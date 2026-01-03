#!/bin/bash
set -e

# ==========================================
#  🔄 RESTORE FROM S3
#  Author: AlobExpress Team
#  Description: Restaura backups (Volumes + DB) do S3 para o ambiente local Docker Swarm
# ==========================================

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${GREEN}=== 🔄 Restaurar Backup do S3 ===${RESET}"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}Este script precisa ser executado como root (sudo).${RESET}"
   exit 1
fi

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker não encontrado. Este script requer Docker.${RESET}"
    exit 1
fi

# Diretório Temporário
RESTORE_DIR="/tmp/restore_s3_temp"
rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"

# ===== 1. CREDENCIAIS E CONFIGURAÇÃO =====
echo -e "${CYAN}Configuração de Credenciais S3 e Ambiente${RESET}"

# Identificar Negócio
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
if [ -z "$BUSINESS_NAME" ]; then BUSINESS_NAME="alobexpress"; fi

# Identificar Cloud Provider (para localizar pasta de backup)
if [ -z "$CLOUD_PROVIDER" ]; then
    while true; do
        read -p "☁️  Provedor Cloud (ex: aws, gcp): " INPUT_CLOUD
        # Permite vazio para fallback padrão "aws", mas se digitar, valida
        if [ -z "$INPUT_CLOUD" ]; then
             break
        fi
        if [[ "$INPUT_CLOUD" =~ ^[a-zA-Z]{1,7}$ ]]; then
            CLOUD_PROVIDER="$INPUT_CLOUD"
            break
        else
            echo -e "${RED}Erro: Digite apenas letras (máximo 7), sem espaços.${RESET}"
        fi
    done
fi
if [ -z "$CLOUD_PROVIDER" ]; then CLOUD_PROVIDER="aws"; fi

# Identificar VM (para localizar pasta de backup)
if [ -z "$INSTANCE_NAME" ]; then
    while true; do
        DEFAULT_VM=$(hostname)
        read -p "🖥️  Nome da VM original (Enter para usar '$DEFAULT_VM'): " INPUT_VM
        if [ -z "$INPUT_VM" ]; then 
            INSTANCE_NAME="$DEFAULT_VM"
            break
        fi
        
        if [[ "$INPUT_VM" =~ ^[a-z0-9-]{1,30}$ ]]; then
            INSTANCE_NAME="$INPUT_VM"
            break
        else
            echo -e "${RED}Erro: Digite apenas letras minúsculas, números ou hífens (máximo 30).${RESET}"
        fi
    done
fi

INSTALL_DIR="/opt/infra/${BUSINESS_NAME}"
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Diretório de instalação $INSTALL_DIR não encontrado. Verifique se o nome do negócio está correto.${RESET}"
    # Fallback genérico apenas se necessário, ou remover
fi

# Tentar ler de variáveis de ambiente ou input
if [ -z "$S3_BUCKET" ]; then read -p "🪣 Nome do Bucket S3: " S3_BUCKET; fi
if [ -z "$S3_REGION" ]; then read -p "🌍 Região S3 (ex: us-east-1): " S3_REGION; fi
if [ -z "$S3_ACCESS_KEY" ]; then read -p "🗝️ AWS Access Key ID: " S3_ACCESS_KEY; fi
if [ -z "$S3_SECRET_KEY" ]; then read -s -p "🔒 AWS Secret Access Key: " S3_SECRET_KEY; echo ""; fi
if [ -z "$S3_ENDPOINT" ]; then read -p "🔗 Endpoint S3 Custom (Enter para AWS padrão): " S3_ENDPOINT; fi

# Função para rodar AWS CLI via Docker
run_aws() {
    local CMD="$1"
    local EXTRA_ARGS=""
    if [ -n "$S3_ENDPOINT" ]; then EXTRA_ARGS="--endpoint-url $S3_ENDPOINT"; fi
    
    docker run --rm \
        -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" \
        -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
        -e AWS_DEFAULT_REGION="$S3_REGION" \
        amazon/aws-cli $CMD $EXTRA_ARGS
}

# ===== 2. SELECIONAR BACKUP =====
# Tenta estrutura nova: backups/{BUSINESS}_{CLOUD}_{VM}
TARGET_FOLDER_FULL="backups/${BUSINESS_NAME}_${CLOUD_PROVIDER}_${INSTANCE_NAME}"
TARGET_FOLDER_PARTIAL="backups/${BUSINESS_NAME}_${CLOUD_PROVIDER}"

echo -e "\n${YELLOW}🔎 Procurando pasta de backups...${RESET}"

if [ -n "$INSTANCE_NAME" ] && run_aws "s3 ls s3://$S3_BUCKET/$TARGET_FOLDER_FULL/" >/dev/null 2>&1; then
    BACKUP_FOLDER="$TARGET_FOLDER_FULL"
    echo -e "${GREEN}✅ Pasta encontrada: $BACKUP_FOLDER${RESET}"
elif run_aws "s3 ls s3://$S3_BUCKET/$TARGET_FOLDER_PARTIAL/" >/dev/null 2>&1; then
    BACKUP_FOLDER="$TARGET_FOLDER_PARTIAL"
    echo -e "${GREEN}✅ Pasta encontrada: $BACKUP_FOLDER${RESET}"
else
    echo -e "${YELLOW}Pastas específicas não encontradas. Buscando na pasta raiz 'backups/'...${RESET}"
    BACKUP_FOLDER="backups"
fi

echo -e "\n${YELLOW}🔎 Listando arquivos em s3://$S3_BUCKET/$BACKUP_FOLDER/...${RESET}"
run_aws "s3 ls s3://$S3_BUCKET/$BACKUP_FOLDER/"

echo -e ""
read -p "📝 Digite o nome do arquivo para restaurar (ex: backup_YYYYMMDD_HHMMSS.tar.gz): " BACKUP_FILE

if [ -z "$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Arquivo não especificado. Abortando.${RESET}"
    exit 1
fi

# ===== 3. DOWNLOAD =====
echo -e "\n${YELLOW}⬇️ Baixando $BACKUP_FILE de $BACKUP_FOLDER...${RESET}"

AWS_CMD="s3 cp s3://$S3_BUCKET/$BACKUP_FOLDER/$BACKUP_FILE /restore/$BACKUP_FILE"
if [ -n "$S3_ENDPOINT" ]; then AWS_CMD="$AWS_CMD --endpoint-url $S3_ENDPOINT"; fi

docker run --rm \
    -v "$RESTORE_DIR:/restore" \
    -e AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY" \
    -e AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY" \
    -e AWS_DEFAULT_REGION="$S3_REGION" \
    amazon/aws-cli $AWS_CMD

if [ ! -f "$RESTORE_DIR/$BACKUP_FILE" ]; then
    echo -e "${RED}❌ Erro ao baixar arquivo. Verifique o nome e credenciais.${RESET}"
    exit 1
fi

# ===== 4. EXTRAÇÃO =====
echo -e "${YELLOW}📦 Extraindo backup...${RESET}"
tar -xzf "$RESTORE_DIR/$BACKUP_FILE" -C "$RESTORE_DIR"

# Compatibilidade: Se existir a pasta 'backup_content' (nova estrutura), mover arquivos para a raiz do restore
if [ -d "$RESTORE_DIR/backup_content" ]; then
    echo -e "📂 Detectada estrutura nova de backup. Ajustando arquivos..."
    # Move conteúdo de backup_content para RESTORE_DIR (incluindo ocultos se houver)
    # mv não move arquivos ocultos com *, mas aqui não temos ocultos críticos
    mv "$RESTORE_DIR/backup_content"/* "$RESTORE_DIR/" 2>/dev/null || true
    rmdir "$RESTORE_DIR/backup_content"
fi

# ===== 5. RESTAURAR VOLUMES =====
echo -e "\n${RED}⚠️  ATENÇÃO: Para restaurar volumes, é RECOMENDADO parar os serviços que usam os volumes.${RESET}"
echo -e "Se você continuar sem parar, os dados podem ficar corrompidos ou não serem atualizados."
read -p "Deseja parar a stack 'alobexpress' agora? (s/n): " STOP_STACK

if [[ "$STOP_STACK" =~ ^(s|S|sim|SIM)$ ]]; then
    echo -e "${YELLOW}Parando todas as stacks ativas...${RESET}"
    # Remove todas as stacks listadas pelo docker stack ls
    docker stack ls --format "{{.Name}}" | xargs -r docker stack rm || true
    echo -e "Aguardando 20 segundos para encerramento dos containers..."
    sleep 20
fi

restore_volume() {
    local SOURCE_NAME="$1" # Nome da pasta no backup
    local DEST_VOL="$2"    # Nome do volume Docker
    local VOL_PATH="/var/lib/docker/volumes/$DEST_VOL/_data"
    
    if [ -d "$RESTORE_DIR/volumes/$SOURCE_NAME" ]; then
        echo -e "  🔄 Restaurando volume ${BOLD}$DEST_VOL${RESET}..."
        
        # Criar volume se não existir
        docker volume create "$DEST_VOL" >/dev/null 2>&1 || true
        
        # Copiar dados (usando cp -a para preservar permissões e arquivos ocultos)
        # O diretório _data deve existir após docker volume create
        cp -a "$RESTORE_DIR/volumes/$SOURCE_NAME/." "$VOL_PATH/"
        echo -e "     ✅ OK"
    else
        echo -e "  ⚠️  Backup do volume $DEST_VOL (origem: $SOURCE_NAME) não encontrado. Pulando."
    fi
}

echo -e "\n${CYAN}Restaurando Volumes...${RESET}"
restore_volume "evolution_instances" "evolution_v2_data"
restore_volume "portainer_data" "portainer_data"
restore_volume "traefik_certs" "volume_swarm_certificates"
restore_volume "n8n_data" "n8n_data"
restore_volume "dify_storage" "dify_storage"

# ===== 6. RESTAURAR BANCO DE DADOS =====
echo -e "\n${CYAN}Restaurando Bancos de Dados...${RESET}"
echo -e "${YELLOW}ℹ️  Para restaurar o banco SQL, o container Postgres precisa estar RODANDO.${RESET}"

if [[ "$STOP_STACK" =~ ^(s|S|sim|SIM)$ ]]; then
    echo -e "\nComo a stack foi parada, você tem duas opções:"
    echo -e "1. Iniciar a stack completa agora (docker stack deploy...)"
    echo -e "2. Sair e restaurar o banco manualmente depois"
    echo -e ""
    read -p "Deseja tentar iniciar a stack agora para restaurar o banco? (s/n): " START_STACK
    
    if [[ "$START_STACK" =~ ^(s|S|sim|SIM)$ ]]; then
        # Tentar encontrar o docker-compose.yml ou executar comando de deploy se soubermos onde está
        COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
        
        if [ -f "$COMPOSE_FILE" ]; then
            echo -e "${GREEN}Encontrado $COMPOSE_FILE. Iniciando stack...${RESET}"
            docker stack deploy -c "$COMPOSE_FILE" alobexpress
            echo -e "Aguardando 30 segundos para inicialização do Postgres..."
            sleep 30
        else
            echo -e "${YELLOW}Arquivo docker-compose.yml não encontrado em $COMPOSE_FILE.${RESET}"
            echo -e "${YELLOW}Como o setup usa múltiplos arquivos, tente reiniciar manualmente os serviços.${RESET}"
            echo -e "Dica: Execute o setup novamente ou use 'docker stack deploy' para cada serviço."
            # Não falha aqui, apenas avisa
        fi
    else
        echo -e "${YELLOW}Pulei a restauração do banco. Os arquivos SQL estão em $RESTORE_DIR se precisar.${RESET}"
        echo -e "Quando o postgres estiver online, use: cat $RESTORE_DIR/postgres_dump.sql | docker exec -i ID_CONTAINER psql -U postgres"
        exit 0
    fi
fi

# Tentar encontrar container Postgres
echo -e "Procurando container Postgres..."
POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)

if [ -n "$POSTGRES_CONTAINER" ]; then
    if [ -f "$RESTORE_DIR/postgres_dump.sql" ]; then
        echo -e "🔄 Restaurando Postgres Main (Isso pode demorar)..."
        cat "$RESTORE_DIR/postgres_dump.sql" | docker exec -i "$POSTGRES_CONTAINER" psql -U postgres
        echo -e "✅ Postgres Restaurado!"
    else
        echo -e "⚠️  Arquivo postgres_dump.sql não encontrado no backup."
    fi
else
    echo -e "${RED}❌ Container Postgres não encontrado (está rodando?). Pulei restauração do banco.${RESET}"
fi

# Tentar encontrar container PgVector (Dify)
PGVECTOR_CONTAINER=$(docker ps -q -f name=pgvector)
if [ -z "$PGVECTOR_CONTAINER" ]; then PGVECTOR_CONTAINER=$(docker ps -q -f name=dify_pgvector); fi

if [ -n "$PGVECTOR_CONTAINER" ]; then
    if [ -f "$RESTORE_DIR/dify_pgvector_dump.sql" ]; then
        echo -e "🔄 Restaurando Dify PgVector..."
        cat "$RESTORE_DIR/dify_pgvector_dump.sql" | docker exec -i "$PGVECTOR_CONTAINER" psql -U postgres
        echo -e "✅ PgVector Restaurado!"
    fi
else
    # Opcional, nem sempre o Dify está instalado
    echo -e "${DIM}Container PgVector não encontrado (Dify não instalado ou parado).${RESET}"
fi

# ===== 7. LIMPEZA =====
echo -e "\n${GREEN}Limpeza de arquivos temporários...${RESET}"
rm -rf "$RESTORE_DIR"

echo -e "\n${GREEN}✅✅ RESTAURAÇÃO CONCLUÍDA COM SUCESSO! ✅✅${RESET}"
echo -e "Verifique os logs dos serviços para garantir que tudo voltou ao normal."
