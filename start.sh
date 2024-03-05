#!/bin/bash
set -e

if [ -z "$AZP_URL" ]; then
  echo 1>&2 "error: olvido la variable de ambiente AZP_URL"
  exit 1
fi

if [ -z "$AZP_TOKEN_FILE" ]; then
  if [ -z "$AZP_TOKEN" ]; then
    echo 1>&2 "error: olvido la variable de ambiente AZP_TOKEN"
    exit 1
  fi

  AZP_TOKEN_FILE=/opt/app-root/app/.token
  echo -n $AZP_TOKEN > "$AZP_TOKEN_FILE"
fi

unset AZP_TOKEN

if [ -n "$AZP_WORK" ]; then
  mkdir -p "$AZP_WORK"
fi

cleanup() {
  if [ -e config.sh ]; then
    print_header "Limpiar. Eliminando el agente de Azure Pipelines..."

    # If the agent has some running jobs, the configuration removal process will fail.
    # So, give it some time to finish the job.
    while true; do
      ./config.sh remove --unattended --auth PAT --token $(cat "$AZP_TOKEN_FILE") && break

      echo "Reintentando en 30 segundos..."
      sleep 30
    done
  fi
}

print_header() {
  lightcyan='\033[1;36m'
  nocolor='\033[0m'
  echo -e "${lightcyan}$1${nocolor}"
}

# Let the agent ignore the token env variables
export VSO_AGENT_IGNORE=AZP_TOKEN,AZP_TOKEN_FILE

source ./env.sh

print_header "Configurando el agente Azure Pipelines..."

# Determine if proxy variables are set
if [[ -z "$AZP_PROXY_URL" ]]; then
  print_header "Agente configurado sin proxy"
  ./config.sh --unattended \
    --agent "${AZP_AGENT_NAME:-$HOSTNAME}" \
    --url "$AZP_URL" \
    --auth PAT \
    --token $(cat "$AZP_TOKEN_FILE") \
    --pool "${AZP_POOL:-Default}" \
    --work "${AZP_WORK:-_work}" \
    --replace \
    --acceptTeeEula & wait $!

elif [[ -z "$AZP_PROXY_USERNAME" || -z "$AZP_PROXY_PASSWORD" ]]; then
  print_header "Agente configurado para usar proxy no autenticado: $AZP_PROXY_URL"
  ./config.sh --unattended \
    --agent "${AZP_AGENT_NAME:-$HOSTNAME}" \
    --url "$AZP_URL" \
    --auth PAT \
    --token $(cat "$AZP_TOKEN_FILE") \
    --pool "${AZP_POOL:-Default}" \
    --work "${AZP_WORK:-_work}" \
    --proxyurl "$AZP_PROXY_URL" \
    --replace \
    --acceptTeeEula & wait $!

else
  print_header "Agente configurado para usar proxy autenticado: $AZP_PROXY_URL"
  ./config.sh --unattended \
    --agent "${AZP_AGENT_NAME:-$HOSTNAME}" \
    --url "$AZP_URL" \
    --auth PAT \
    --token $(cat "$AZP_TOKEN_FILE") \
    --pool "${AZP_POOL:-Default}" \
    --work "${AZP_WORK:-_work}" \
    --proxyurl "$AZP_PROXY_URL" \
    --proxyusername "$AZP_PROXY_USERNAME" \
    --proxypassword "$AZP_PROXY_PASSWORD" \
    --replace \
    --acceptTeeEula & wait $!
fi

unset AZP_PROXY_URL AZP_PROXY_USERNAME AZP_PROXY_PASSWORD

print_header "Ejecutando el agente de Azure Pipelines..."

trap 'cleanup; exit 0' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

# To be aware of TERM and INT signals call run.sh
# Running it with the --once flag at the end will shut down the agent after the build is executed
./run-docker.sh "$@" & wait $!
