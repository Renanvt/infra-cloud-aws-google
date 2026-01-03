#!/bin/bash

define_resources() {
    print_step "DEFININDO RECURSOS DA VM"

    # Recursos Base (Infra)
    TRAEFIK_LIMIT_CPU="1"
    TRAEFIK_LIMIT_RAM="1024M"
    TRAEFIK_REQ_CPU=".1"
    TRAEFIK_REQ_RAM="128M"

    if [ "$ENABLE_DIFY" = true ]; then
        print_info "Modo High-Spec (Com Dify) ativado."
        # High Spec (Baseado em vm/)
        # Postgres
        POSTGRES_LIMIT_CPU="3.2"
        POSTGRES_LIMIT_RAM="12801M"
        POSTGRES_REQ_CPU=".4"
        POSTGRES_REQ_RAM="1600M"
        
        # Redis
        REDIS_LIMIT_CPU="1"
        REDIS_LIMIT_RAM="1024M"
        REDIS_REQ_CPU=".1"
        REDIS_REQ_RAM="128M"

        # Evolution
        EVO_LIMIT_CPU="2"
        EVO_LIMIT_RAM="4096M"
        EVO_REQ_CPU=".4"
        EVO_REQ_RAM="1024M"
        
        # N8N (High)
        N8N_LIMIT_CPU="2"
        N8N_LIMIT_RAM="4096M"
        N8N_REQ_CPU=".4"
        N8N_REQ_RAM="1024M"
        
        # RabbitMQ
        RABBITMQ_LIMIT_CPU="2"
        RABBITMQ_LIMIT_RAM="1024M"

        # Dify (High)
        DIFY_LIMIT_CPU="2"
        DIFY_LIMIT_RAM="2048M"
        DIFY_REQ_CPU=".2"
        DIFY_REQ_RAM="512M"

    else
        print_info "Modo Low-Spec (Sem Dify - 4GB RAM) ativado."
        # Low Spec (4GB RAM Total)
        # Postgres
        POSTGRES_LIMIT_CPU="1"
        POSTGRES_LIMIT_RAM="1024M"
        POSTGRES_REQ_CPU=".1"
        POSTGRES_REQ_RAM="256M"
        
        # Redis
        REDIS_LIMIT_CPU="1"
        REDIS_LIMIT_RAM="512M"
        REDIS_REQ_CPU=".1"
        REDIS_REQ_RAM="128M"

        # Evolution
        EVO_LIMIT_CPU="1"
        EVO_LIMIT_RAM="1024M"
        EVO_REQ_CPU=".1"
        EVO_REQ_RAM="256M"
        
        # N8N (Low)
        N8N_LIMIT_CPU="1"
        N8N_LIMIT_RAM="1024M"
        N8N_REQ_CPU=".1"
        N8N_REQ_RAM="256M"
        
        # RabbitMQ
        RABBITMQ_LIMIT_CPU="1"
        RABBITMQ_LIMIT_RAM="512M"

        # Dify (Low - Dummy)
        DIFY_LIMIT_CPU="1"
        DIFY_LIMIT_RAM="1024M"
        DIFY_REQ_CPU=".1"
        DIFY_REQ_RAM="256M"
    fi

    # Export variables to make them available to other scripts
    export TRAEFIK_LIMIT_CPU TRAEFIK_LIMIT_RAM TRAEFIK_REQ_CPU TRAEFIK_REQ_RAM
    export POSTGRES_LIMIT_CPU POSTGRES_LIMIT_RAM POSTGRES_REQ_CPU POSTGRES_REQ_RAM
    export REDIS_LIMIT_CPU REDIS_LIMIT_RAM REDIS_REQ_CPU REDIS_REQ_RAM
    export EVO_LIMIT_CPU EVO_LIMIT_RAM EVO_REQ_CPU EVO_REQ_RAM
    export N8N_LIMIT_CPU N8N_LIMIT_RAM N8N_REQ_CPU N8N_REQ_RAM
    export RABBITMQ_LIMIT_CPU RABBITMQ_LIMIT_RAM
    export DIFY_LIMIT_CPU DIFY_LIMIT_RAM DIFY_REQ_CPU DIFY_REQ_RAM
}
