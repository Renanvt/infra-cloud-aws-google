#!/bin/bash

deploy_services() {
    print_step "INICIANDO SERVIÇOS DE INFRAESTRUTURA"
    
    # 1. Traefik e Portainer
    print_info "Deploying Traefik..."
    docker stack deploy --detach=true -c 04.traefik.yaml traefik >/dev/null 2>&1
    print_info "Deploying Portainer..."
    docker stack deploy --detach=true -c 05.portainer.yaml portainer >/dev/null 2>&1
    
    print_info "Aguardando serviços de infraestrutura subirem (15s)..."
    sleep 15
    
    # 2. Bancos de Dados
    print_info "Deploying Postgres..."
    docker stack deploy --detach=true -c 06.postgres.yaml postgres >/dev/null 2>&1
    print_info "Deploying Redis..."
    docker stack deploy --detach=true -c 07.redis.yaml redis >/dev/null 2>&1
    print_info "Deploying RabbitMQ..."
    docker stack deploy --detach=true -c 11.rabbitmq.yaml rabbitmq >/dev/null 2>&1
    
    print_info "Aguardando bancos de dados e RabbitMQ inicializarem (30s)..."
    sleep 30

    # 3. Criação do Banco N8N
    print_step "CONFIGURANDO BANCO DE DADOS N8N"
    print_info "Tentando conectar ao Postgres para criar o banco 'n8n'..."
    
    # Loop para encontrar o container ID do postgres (pode demorar um pouco no swarm)
    POSTGRES_CONTAINER=""
    for i in {1..10}; do
        POSTGRES_CONTAINER=$(docker ps -q -f name=postgres_postgres)
        if [ -n "$POSTGRES_CONTAINER" ]; then
            break
        fi
        sleep 2
    done

    if [ -n "$POSTGRES_CONTAINER" ]; then
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE n8n;" >/dev/null 2>&1; then
            print_success "Banco de dados 'n8n' criado com sucesso!"
        else
            print_warning "Banco de dados 'n8n' já existe ou erro na criação (verifique logs)."
        fi
        
        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE evolution;" >/dev/null 2>&1; then
            print_success "Banco de dados 'evolution' criado com sucesso!"
        else
            print_warning "Banco de dados 'evolution' já existe ou erro na criação (verifique logs)."
        fi

        if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE chatwoot;" >/dev/null 2>&1; then
            print_success "Banco de dados 'chatwoot' criado com sucesso!"
        else
            print_warning "Banco de dados 'chatwoot' já existe ou erro na criação (verifique logs)."
        fi

        if [ "$ENABLE_DIFY" = true ]; then
            if docker exec -i "$POSTGRES_CONTAINER" psql -U postgres -c "CREATE DATABASE dify;" >/dev/null 2>&1; then
                print_success "Banco de dados 'dify' criado com sucesso!"
            else
                print_warning "Banco de dados 'dify' já existe ou erro na criação (verifique logs)."
            fi
        fi
    else
        print_error "Não foi possível encontrar o container do Postgres. Crie os bancos 'n8n', 'evolution' e 'chatwoot' manualmente depois."
    fi

    # 4. Deploy Aplicações
    print_step "DEPLOY DAS APLICAÇÕES DE NEGÓCIO"
    
    # Criar volume externo para Evolution
    docker volume create evolution_v2_data >/dev/null
    
    print_info "Deploying N8N Editor..."
    docker stack deploy --detach=true -c 08.n8n-editor.yaml n8n_editor >/dev/null 2>&1
    print_info "Deploying N8N Worker..."
    docker stack deploy --detach=true -c 09.n8n-workers.yaml n8n_worker >/dev/null 2>&1
    print_info "Deploying N8N Webhook..."
    docker stack deploy --detach=true -c 10.n8n-webhooks.yaml n8n_webhook >/dev/null 2>&1
    print_info "Deploying Evolution V2..."
    docker stack deploy --detach=true -c 18.evolution_v2.yaml evolution_v2 >/dev/null 2>&1

    if [ "$ENABLE_DIFY" = true ]; then
        print_info "Realizando deploy do Dify AI..."
        # Criar volumes externos para Dify se necessário
        docker volume create pgvector_data >/dev/null
        docker volume create dify_plugin_cwd >/dev/null

        # 1. Deploy PGVector e Sandbox (Dependências)
        print_info "Deploying Dify PGVector & Sandbox..."
        docker stack deploy --detach=true -c 12.dify-pgvector.yaml dify_pgvector >/dev/null 2>&1
        docker stack deploy --detach=true -c 13.dify-sandbox.yaml dify_sandbox >/dev/null 2>&1
        
        # 2. Deploy API (Migration)
        print_info "Iniciando Dify API (Migrações de Banco de Dados)..."
        docker stack deploy --detach=true -c 15.dify-api.yaml dify_api >/dev/null 2>&1
        print_info "Aguardando migrações do Dify API (45s)..."
        sleep 45

        # 3. Deploy Plugin Daemon
        print_info "Deploying Dify Plugin Daemon..."
        docker stack deploy --detach=true -c 17.dify-plugindaemon.yaml dify_plugin_daemon >/dev/null 2>&1

        # 4. Deploy Web e Worker
        print_info "Deploying Dify Web & Worker..."
        docker stack deploy --detach=true -c 14.dify-web.yaml dify_web >/dev/null 2>&1
        docker stack deploy --detach=true -c 16.dify-worker.yaml dify_worker >/dev/null 2>&1
    fi
}

print_summary() {
    # Resumo Final
    print_step "SETUP CONCLUÍDO!"
    if [ "$IS_AWS" = true ]; then
        echo -e "${GREEN}✅ Infraestrutura AWS (Swarm) implantada!${RESET}"
    else
        echo -e "${GREEN}✅ Infraestrutura Google Cloud (Swarm) implantada!${RESET}"
    fi
    echo ""
    echo -e "${BOLD}${CYAN}Acesse seus serviços:${RESET}"
    echo -e "   ${ARROW} Portainer: https://${PORTAINER_DOMAIN}"
    echo -e "   ${ARROW} N8N Editor: https://${N8N_EDITOR_DOMAIN}"
    echo -e "   ${ARROW} N8N Webhook: https://${N8N_WEBHOOK_DOMAIN}"
    echo -e "   ${ARROW} RabbitMQ Panel: https://${RABBITMQ_DOMAIN}"
    echo -e "   ${ARROW} Evolution API: https://${EVOLUTION_DOMAIN}"
    echo -e "   ${ARROW} Evolution Manager: https://${EVOLUTION_DOMAIN}/manager"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${ARROW} Dify Web: https://${DIFY_WEB_DOMAIN}"
        echo -e "   ${ARROW} Dify API: https://${DIFY_API_DOMAIN}"
    fi

    echo ""
    echo -e "${YELLOW}⚠️  Configure sua senha de administrador no Portainer imediatamente!${RESET}"
    echo -e "   Link direto: https://${PORTAINER_DOMAIN}"
    echo ""
    echo -e "${BOLD}${MAGENTA}🔒 CREDENCIAIS GERADAS (SALVE AGORA!):${RESET}"
    echo -e "   ${WHITE}Postgres Password:${RESET} ${POSTGRES_PASSWORD}"
    echo -e "   ${WHITE}Redis Password:${RESET} ${REDIS_PASSWORD}"
    echo -e "   ${WHITE}RabbitMQ User/Pass:${RESET} ${RABBITMQ_USER} / ${RABBITMQ_PASSWORD}"
    echo -e "   ${WHITE}N8N Encryption Key:${RESET} ${N8N_ENCRYPTION_KEY}"
    echo -e "   ${WHITE}Evolution Global API Key:${RESET} ${EVOLUTION_API_KEY}"
    
    if [ "$ENABLE_DIFY" = true ]; then
        echo -e "   ${WHITE}Dify Secret Key:${RESET} ${DIFY_SECRET_KEY}"
        echo -e "   ${WHITE}Dify Inner API Key (Plugin Daemon):${RESET} ${DIFY_INNER_API_KEY}"
    else
        echo -e "${DIM}Dify não foi instalado.${RESET}"
    fi
    echo ""

    setup_auto_backup
    
    if [ "$ENABLE_DIFY" = true ]; then
        # setup_dify_resource_monitor # Function not found in original script
        print_warning "setup_dify_resource_monitor skipped (not found)"
    fi
}
