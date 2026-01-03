# Documentação da Infraestrutura Alob Express (v2.0.1)

## 🏗️ Visão Geral da Arquitetura

O projeto adota uma arquitetura de **Monólito Modular Baseado em Features**, facilitando a manutenção, escalabilidade e implantação de serviços de infraestrutura para automação e IA.

### Estrutura de Diretórios

A estrutura foi reorganizada para evitar scripts monolíticos gigantescos, dividindo responsabilidades em módulos específicos:

```
d:\workspace\infra\infra-alob-express\
├── install.sh                  # Orquestrador principal da instalação
├── modules/
│   ├── core/                   # Funcionalidades centrais (Deploy, Resources, Setup Base)
│   ├── shared/                 # Utilitários compartilhados (Logging, Input, Backup)
│   ├── dify/                   # Configuração específica do Dify (IA)
│   ├── evolution/              # Configuração específica do Evolution API
│   └── n8n/                    # Configuração específica do n8n (Automação)
├── docs/                       # Documentação do projeto
└── img/                        # Recursos visuais e evidências de custos
```

## 🚀 Processo de Instalação

O script `install.sh` atua como o ponto de entrada único. Ele coordena a execução dos módulos na seguinte ordem:

1.  **Setup Inicial**: Configuração de logs, verificação de permissões (root) e dependências.
2.  **Configuração de Negócio**: Coleta do nome da empresa para isolamento de recursos.
3.  **Seleção de Nuvem**: Detecção ou escolha do provedor (AWS vs Outros) e inicialização do Docker Swarm.
4.  **Verificação de DNS**: Validação dos apontamentos DNS necessários.
5.  **Coleta de Variáveis**: Interação com o usuário para definir segredos e configurações de cada serviço (Core, N8N, Evolution, Dify).
6.  **Definição de Recursos**: Escolha entre modo "High-Spec" (com Dify) ou "Low-Spec" (apenas automação leve).
7.  **Geração de YAMLs**: Criação dinâmica dos arquivos `docker-compose` baseada nas variáveis coletadas.
8.  **Deploy**: Implantação das stacks no Swarm e execução de migrações de banco de dados.

## 📂 Localização dos Arquivos de Configuração

Durante a instalação, os arquivos de configuração `.yaml` (Docker Compose) e arquivos de ambiente (`.env`) são gerados e salvos no diretório de instalação definido para o negócio:

**Caminho Padrão:** `/opt/infra/<NOME_DO_NEGOCIO>/`

Exemplo: Se o nome do negócio for `minha-empresa`, os arquivos estarão em `/opt/infra/minha-empresa/`.

## 🛠️ Módulos e Componentes

### Core
- **Traefik**: Reverse Proxy e gerenciamento de certificados SSL (Let's Encrypt).
- **Portainer**: Interface de gerenciamento para o Docker Swarm.
- **Redis/Postgres**: Serviços de dados compartilhados.

### Evolution API
- Integração com WhatsApp.
- Configuração automática de buckets S3 para mídia.
- Tratamento de endpoint S3 (remoção de protocolo `https://`).

### Dify (IA)
- Plataforma de desenvolvimento de aplicações LLM.
- Inclui API, Worker e Web interface.
- Configuração de armazenamento S3 (adiciona prefixo `https://` se necessário).
- **Nota**: Requer mais recursos de hardware (High-Spec).

### N8N (Automação)
- Orquestração de fluxos de trabalho.
- Persistência de dados e integração com Webhooks.

## 💰 Custos e Dimensionamento

O projeto foi otimizado para equilibrar performance e custo. Consulte o `README.md` para detalhes visuais sobre o breakdown de custos mensais e projeções reais.

---
**Versão**: 2.0.1
**Data**: 2025-12-31
