#!/bin/bash

##########################
# Etapa 1
#
# obter e rodar o script de inicialização no cluster
#
##########################

# Inicia o Swarm

#docker swarm init --advertise-addr={{ip_externo}}
## “Se o IP público vem por NAT(Google Cloud) → nunca usar no Swarm. Deixe como padrão(usando o ip interno)”
##“Se o IP público é direto na interface → pode funcionar, mas evite”
##########################
# Etapa 2
#
# Configura a Rede do Docker Swarm
#

docker network create --driver=overlay network_swarm_public
