#!/bin/bash

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
}

verify_dns() {
    # Aviso DNS Cloudflare
    print_step "VERIFICAÇÃO DE DNS (CLOUDFLARE)"
    echo -e "${YELLOW}Antes de continuar, certifique-se de que os apontamentos DNS foram feitos:${RESET}"
    echo -e "Exemplo de configuração (substitua '${BOLD}meu-dominio.com.br${RESET}' pelo seu):"
    echo -e ""
    echo -e "   ${BOLD}1. Registro A (Principal):${RESET}"
    echo -e "      Nome: ${CYAN}automations${RESET} → IP: ${BOLD}IP_VM${RESET}"
    echo -e ""
    echo -e "   ${BOLD}2. Registros CNAME (Apontando para 'automations.meu-dominio.com.br'):${RESET}"
    echo -e "      - ${CYAN}painel${RESET}  (Portainer)"
    echo -e "      - ${CYAN}n8neditor${RESET}        (N8N Editor)"
    echo -e "      - ${CYAN}n8nwebhook${RESET}          (N8N Webhook)"
    echo -e "      - ${CYAN}rabbit${RESET}         (RabbitMQ)"
    echo -e "      - ${CYAN}evolutionapi${RESET}     (Evolution API)"
    echo -e "      - ${CYAN}difyapi${RESET}       (Dify API - Opcional)"
    echo -e "      - ${CYAN}difyeditor${RESET}       (Dify Web - Opcional)"
    echo -e ""
    echo -e "${DIM}Sugestão: Você pode usar outros prefixos como 'portainer', 'n8n', 'api', etc.${RESET}"
    echo -e "4. Use 'DNS Only' (Nuvem Cinza) no Cloudflare inicialmente para gerar SSL"
    read -p "$(echo -e ${BOLD}${GREEN}"Os DNS estão configurados corretamente? (s/n): "${RESET})" DNS_CONFIRM < /dev/tty
    if [[ ! "$DNS_CONFIRM" =~ ^(s|S|sim|SIM)$ ]]; then 
        print_error "Configure o DNS e execute novamente."
        exit 0
    fi
}
