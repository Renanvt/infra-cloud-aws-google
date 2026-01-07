#!/bin/bash

setup_core_vars() {
    print_banner
    print_step "PASSO 2: DEPLOY DOS SERVIÇOS - CONFIGURAÇÃO"
    
    print_step "CONFIGURAÇÃO PORTAINER, TRAEFIK E RABBIT"
    confirm_input "${CYAN}📧 E-mail para SSL (Traefik): ${RESET}" "E-mail SSL:" TRAEFIK_EMAIL

    # Domínios Core
    confirm_input "${CYAN} Domínio Portainer (ex: painel.meudominio.com): ${RESET}" "Portainer será:" PORTAINER_DOMAIN
    confirm_input "${CYAN}🌐 Domínio RabbitMQ (ex: rabbit.meudominio.com): ${RESET}" "RabbitMQ será:" RABBITMQ_DOMAIN

    print_banner
    print_step "CONFIGURAÇÕES DE BANCO DE DADOS"
    # Senhas Core
    confirm_input "${CYAN} Senha para Banco de Dados (Postgres): ${RESET}" "Senha Postgres:" POSTGRES_PASSWORD
    confirm_input "${CYAN}🔑 Senha para Redis: ${RESET}" "Senha Redis:" REDIS_PASSWORD
    
    # RabbitMQ Credenciais
    confirm_input "${CYAN}👤 Usuário RabbitMQ (Padrão: admin): ${RESET}" "Usuário RabbitMQ:" RABBITMQ_USER
    if [ -z "$RABBITMQ_USER" ]; then RABBITMQ_USER="admin"; fi
    
    confirm_input "${CYAN}🔑 Senha para RabbitMQ: ${RESET}" "Senha RabbitMQ:" RABBITMQ_PASSWORD

    export TRAEFIK_EMAIL PORTAINER_DOMAIN RABBITMQ_DOMAIN POSTGRES_PASSWORD REDIS_PASSWORD RABBITMQ_USER RABBITMQ_PASSWORD
}
