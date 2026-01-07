#!/bin/bash

# ==============================================================================
#  TRAE AI - INFRASTRUCTURE SETUP
#  Modularized version of the original setup script
# ==============================================================================

# Directory where the script is running
if [ -z "${BASH_SOURCE[0]}" ]; then
    # Running via pipe/curl - Use a temporary directory
    SCRIPT_DIR="/tmp/infra-installer-$(date +%s)"
    mkdir -p "$SCRIPT_DIR"
    echo "Running in installer mode. Downloading modules to $SCRIPT_DIR..."
else
    # Running from local file
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

# Repository Base URL (Adjust branch if needed)
REPO_BASE_URL="https://raw.githubusercontent.com/Renanvt/infra-cloud-aws-google/main"

# Function to ensure module exists and source it
ensure_module() {
    local module_path="$1"
    local local_file="$SCRIPT_DIR/$module_path"

    # Only download if not present
    if [ ! -f "$local_file" ]; then
        # echo "Downloading module: $module_path..." # Commented to avoid spamming output
        mkdir -p "$(dirname "$local_file")"
        
        if command -v curl >/dev/null 2>&1; then
            HTTP_CODE=$(curl -sL -w "%{http_code}" "$REPO_BASE_URL/$module_path" -o "$local_file")
            if [ "$HTTP_CODE" -ne 200 ]; then
                echo "Error: Falha ao baixar $module_path (HTTP $HTTP_CODE)"
                rm -f "$local_file"
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            wget -qO "$local_file" "$REPO_BASE_URL/$module_path"
        else
            echo "Erro: curl ou wget não encontrados. Não foi possível baixar os módulos."
            exit 1
        fi
    fi

    source "$local_file"
}

# Load Modules (Order Matters)
MODULES=(
    "modules/shared/utils.sh"
    "modules/shared/inputs.sh"
    "modules/shared/backup.sh"
    "modules/core/setup.sh"
    "modules/core/inputs.sh"
    "modules/core/cloud.sh"
    "modules/core/resources.sh"
    "modules/core/yamls.sh"
    "modules/core/deploy.sh"
    "modules/n8n/setup.sh"
    "modules/evolution/setup.sh"
    "modules/dify/setup.sh"
)

for module in "${MODULES[@]}"; do
    ensure_module "$module"
done

# ==============================================================================
#  MAIN EXECUTION
# ==============================================================================

# 1. Initial Logging & Permissions
setup_logging
print_banner
check_root
detect_hardware

# 2. Business Configuration
print_step "CONFIGURAÇÃO DO NEGÓCIO"
while true; do
    echo -e "${CYAN}Informe o nome do seu negócio (ex: minhaempresa).${RESET}"
    echo -e "${DIM}Isso será usado para personalizar pastas, logs e backups.${RESET}"
    echo -e "${YELLOW}⚠️  Atenção: Use apenas letras minúsculas e números, tudo junto (sem espaços).${RESET}"
    read -p "$(echo -e ${GREEN}"Nome do Negócio: "${RESET})" INPUT_BUSINESS_NAME < /dev/tty || continue

    if [[ -z "$INPUT_BUSINESS_NAME" ]]; then
        print_error "Nome do negócio não pode ser vazio!"
        continue
    fi

    # Verificar se contém apenas letras minúsculas e números
    if [[ ! "$INPUT_BUSINESS_NAME" =~ ^[a-z0-9]+$ ]]; then
        print_error "Formato inválido! Use apenas letras minúsculas e números, sem espaços ou caracteres especiais."
        echo -e "Exemplo correto: ${BOLD}minhaempresa${RESET}"
        echo -e "Exemplo incorreto: ${RED}Minha Empresa${RESET}"
        continue
    fi
    
    BUSINESS_NAME="$INPUT_BUSINESS_NAME"
    break
done

print_success "Negócio configurado como: ${BOLD}$BUSINESS_NAME${RESET}"

# 3. Setup Directories
INSTALL_DIR="/opt/infra/${BUSINESS_NAME}"
LOG_DIR="/var/log/${BUSINESS_NAME}"
mkdir -p "$LOG_DIR"
CHECKPOINT_FILE="${LOG_DIR}/checkpoint"

# Update logging to business directory (if possible/needed)
# setup_logging # Calling again, though it might be skipped if LOGGING_ACTIVE is true

check_recovery

log_message "INFO" "Iniciando setup para o negócio: $BUSINESS_NAME"

print_step "PREPARANDO DIRETÓRIO DE INSTALAÇÃO"
if [ ! -d "$INSTALL_DIR" ]; then
    print_info "Criando diretório: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"
print_success "Diretório de trabalho definido: $(pwd)"
echo ""

# 4. Cloud Selection & Setup (Swarm Init)
print_step "SELEÇÃO DE NUVEM"
run_cloud_setup

# 5. DNS Verification
verify_dns

# 6. Service Configuration (Inputs)
setup_core_vars
setup_n8n_vars
setup_evolution_vars
setup_dify_vars

# 7. Resource Definition
print_banner
define_resources

# 8. Checkpoint
save_checkpoint "inputs_collected"

# 9. YAML Generation
generate_core_yamls
generate_n8n_yamls
generate_evolution_yaml
generate_dify_yamls

print_success "Arquivos YAML gerados com sucesso!"

# 10. Service Deployment
deploy_services

# 11. Final Summary & Backup Setup
print_summary
setup_auto_backup
run_backup_restore_menu
