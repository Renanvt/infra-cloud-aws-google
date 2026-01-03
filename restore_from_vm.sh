#!/bin/bash
set -e

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${GREEN}=== 🔄 Restaurar Backup Local (VM) ===${RESET}"

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

# Diretório Padrão de Backup (o mesmo do backup_to_vm.sh)
DEFAULT_BACKUP_DIR="/opt/infra/backups"
RESTORE_DIR="/tmp/restore_vm_temp"

# Limpar temp anterior
rm -rf "$RESTORE_DIR"
mkdir -p "$RESTORE_DIR"

# ===== 1. LOCALIZAR ARQUIVO DE BACKUP =====
BACKUP_FILE=""

# Verificar se existem backups no diretório padrão
if [ -d "$DEFAULT_BACKUP_DIR" ]; then
    # Lista arquivos .tar.gz ordenados por data (mais recente primeiro)
    BACKUP_COUNT=$(find "$DEFAULT_BACKUP_DIR" -name "*.tar.gz" | wc -l)
    
    if [ "$BACKUP_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}Backups encontrados em $DEFAULT_BACKUP_DIR:${RESET}"
        
        # Array para guardar opções
        options=()
        i=1
        while IFS= read -r file; do
            filename=$(basename "$file")
            echo "  $i) $filename"
            options+=("$file")
            ((i++))
        done < <(ls -t "$DEFAULT_BACKUP_DIR"/*.tar.gz)
        
        echo -e "  0) Fornecer outro caminho manualmente"
        
        read -p "$(echo -e ${CYAN}"Escolha um número para restaurar (1-$((i-1))) ou 0: "${RESET})" CHOICE
        
        if [[ "$CHOICE" =~ ^[1-9][0-9]*$ ]] && [ "$CHOICE" -lt "$i" ]; then
            INDEX=$((CHOICE-1))
            BACKUP_FILE="${options[$INDEX]}"
        fi
    else
        echo -e "${YELLOW}Nenhum backup encontrado na pasta padrão $DEFAULT_BACKUP_DIR.${RESET}"
    fi
fi

# Se não escolheu da lista (ou lista vazia/opção 0), pede manual
if [ -z "$BACKUP_FILE" ]; then
    while true; do
        echo -e ""
        echo -e "${YELLOW}Por favor, forneça o caminho completo do arquivo de backup (.tar.gz).${RESET}"
        read -p "Caminho do arquivo: " MANUAL_PATH
        
        # Remove aspas se o usuário colocou
        MANUAL_PATH=$(echo "$MANUAL_PATH" | tr -d '"' | tr -d "'")
        
        if [ -f "$MANUAL_PATH" ]; then
            if [[ "$MANUAL_PATH" == *.tar.gz ]]; then
                BACKUP_FILE="$MANUAL_PATH"
                break
            else
                echo -e "${RED}O arquivo deve ter extensão .tar.gz.${RESET}"
            fi
        else
            echo -e "${RED}Arquivo não encontrado: $MANUAL_PATH${RESET}"
            read -p "Deseja tentar novamente? (s/n): " RETRY
            if [[ ! "$RETRY" =~ ^(s|S|sim|SIM)$ ]]; then
                echo -e "${RED}Operação cancelada.${RESET}"
                exit 1
            fi
        fi
    done
fi

echo -e "${GREEN}✅ Arquivo selecionado: $BACKUP_FILE${RESET}"

# ===== 2. EXTRAÇÃO =====
echo -e "\n${YELLOW}📦 Extraindo backup...${RESET}"
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"

# Compatibilidade: Se existir a pasta 'backup_content' (estrutura S3), mover arquivos para a raiz do restore
if [ -d "$RESTORE_DIR/backup_content" ]; then
    echo -e "📂 Detectada estrutura aninhada. Ajustando arquivos..."
    mv "$RESTORE_DIR/backup_content"/* "$RESTORE_DIR/" 2>/dev/null || true
    rmdir "$RESTORE_DIR/backup_content"
fi

# ===== 3. RESTAURAR VOLUMES =====
echo -e "\n${RED}⚠️  ATENÇÃO: Para restaurar volumes, é RECOMENDADO parar as stacks.${RESET}"
echo -e "Se você continuar sem parar, os dados podem ficar corrompidos."
read -p "Deseja parar todas as stacks ativas agora? (s/n): " STOP_STACK

if [[ "$STOP_STACK" =~ ^(s|S|sim|SIM)$ ]]; then
    echo -e "${YELLOW}Parando todas as stacks ativas...${RESET}"
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
        
        # Copiar dados (usando cp -a para preservar permissões)
        cp -a "$RESTORE_DIR/volumes/$SOURCE_NAME/." "$VOL_PATH/"
        echo -e "     ✅ OK"
    else
        # Silencioso se não encontrar, pois nem todos os backups tem todos os volumes
        # echo -e "  ⚠️  Volume $DEST_VOL não encontrado no backup."
        :
    fi
}

echo -e "\n${CYAN}Restaurando Volumes...${RESET}"
# Mapeamento: Nome na Pasta -> Nome do Volume Docker
restore_volume "evolution_instances" "evolution_v2_data"
restore_volume "portainer_data" "portainer_data"
restore_volume "traefik_certs" "volume_swarm_certificates"
restore_volume "n8n_data" "n8n_data"
restore_volume "dify_storage" "dify_storage"
restore_volume "dify_plugins" "dify_plugin_cwd"
restore_volume "redis_data" "redis_data"
restore_volume "rabbitmq_data" "rabbitmq_data"
restore_volume "postgres_data" "postgres_data" # Cuidado ao restaurar dados brutos do postgres

# ===== 4. RESTAURAR BANCO DE DADOS =====
echo -e "\n${CYAN}Restaurando Bancos de Dados...${RESET}"

if [[ "$STOP_STACK" =~ ^(s|S|sim|SIM)$ ]]; then
    echo -e "${YELLOW}ℹ️  Para restaurar o banco SQL via dump, o Postgres precisa estar RODANDO.${RESET}"
    echo -e "Como as stacks foram paradas, precisamos reiniciar apenas o banco ou pular esta etapa."
    echo -e "Se você restaurou o volume 'postgres_data' acima (backup bruto), o dump SQL pode não ser necessário."
    echo -e ""
    echo -e "1. Pular restauração SQL (Confiar na restauração do volume físico)"
    echo -e "2. Tentar iniciar Postgres para restaurar dump SQL"
    read -p "Opção (1 ou 2): " DB_OPT

    if [ "$DB_OPT" == "1" ]; then
        echo -e "${GREEN}Pulando restauração SQL via dump.${RESET}"
    else
        # Tentar iniciar stack postgres se possível, ou avisar manual
        echo -e "${YELLOW}Iniciando stack 'postgres' (se existir arquivo)...${RESET}"
        # Tenta achar um yaml de postgres na pasta atual ou /opt/infra
        # Como é genérico, melhor pedir ao usuário para rodar deploy depois
        echo -e "${RED}Não é possível iniciar o Postgres automaticamente de forma segura aqui.${RESET}"
        echo -e "Por favor, após finalizar este script, inicie sua stack e rode manualmente:"
        echo -e "cat $RESTORE_DIR/postgres_dump.sql | docker exec -i ID_CONTAINER psql -U postgres"
    fi
else
    # Se a stack não foi parada, o postgres deve estar online
    POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
    
    if [ -n "$POSTGRES_CONTAINER" ]; then
        if [ -f "$RESTORE_DIR/postgres_dump.sql" ]; then
            echo -e "🔄 Restaurando Postgres Main..."
            cat "$RESTORE_DIR/postgres_dump.sql" | docker exec -i "$POSTGRES_CONTAINER" psql -U postgres
            echo -e "✅ Postgres Restaurado!"
        fi
    else
        echo -e "${YELLOW}Container Postgres não encontrado. Dump SQL não restaurado.${RESET}"
    fi

    # Dify PgVector
    PGVECTOR_CONTAINER=$(docker ps -q -f name=pgvector)
    if [ -z "$PGVECTOR_CONTAINER" ]; then PGVECTOR_CONTAINER=$(docker ps -q -f name=dify_pgvector); fi

    if [ -n "$PGVECTOR_CONTAINER" ] && [ -f "$RESTORE_DIR/dify_pgvector_dump.sql" ]; then
        echo -e "🔄 Restaurando Dify PgVector..."
        cat "$RESTORE_DIR/dify_pgvector_dump.sql" | docker exec -i "$PGVECTOR_CONTAINER" psql -U postgres
        echo -e "✅ PgVector Restaurado!"
    fi
fi

# ===== 5. LIMPEZA =====
echo -e "\n${GREEN}Limpeza de arquivos temporários...${RESET}"
rm -rf "$RESTORE_DIR"

echo -e "\n${GREEN}✅✅ RESTAURAÇÃO LOCAL CONCLUÍDA! ✅✅${RESET}"
echo -e "Se você parou as stacks, lembre-se de iniciá-las novamente."
echo -e "Exemplo: docker stack deploy -c ... "
