#!/usr/bin/env bash

# This script is responsible for running Director with PostgreSQL.

RED='\033[0;31m'
GREEN='\033[0;32m'
INVERTED='\033[7m'
NC='\033[0m' # No Color

set -e

ROOT_PATH=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

POSITIONAL=()
while [[ $# -gt 0 ]]
do

    key="$1"

    case ${key} in
        --skip-app-start)
            SKIP_APP_START=true
            shift # past argument
        ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters


POSTGRES_CONTAINER="test-postgres"
POSTGRES_VERSION="11"

DB_USER="postgres"
DB_PWD="pgsql@12345"
DB_NAME="compass"
DB_PORT="5432"
DB_HOST="127.0.0.1"

function cleanup() {
    echo -e "${GREEN}Cleanup Postgres container${NC}"
    docker rm --force ${POSTGRES_CONTAINER}
}

trap cleanup EXIT

echo -e "${GREEN}Start Postgres in detached mode${NC}"
docker run -d --name ${POSTGRES_CONTAINER} \
            -e POSTGRES_HOST=${DB_HOST} \
            -e POSTGRES_USER=${DB_USER} \
            -e POSTGRES_PASSWORD=${DB_PWD} \
            -e POSTGRES_DB=${DB_NAME} \
            -e POSTGRES_PORT=${DB_PORT} \
            -p ${DB_PORT}:${DB_PORT} \
            postgres:${POSTGRES_VERSION}

set +e
echo '# WAITING FOR CONNECTION WITH DATABASE #'
for i in {1..30}
do
    docker exec ${POSTGRES_CONTAINER} pg_isready -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" -d "${DB_NAME}"
    if [ $? -eq 0 ]
    then
        dbReady=true
        break
    fi
    sleep 1
done

if [ "${dbReady}" != true ] ; then
    echo '# COULD NOT ESTABLISH CONNECTION TO DATABASE #'
    exit 1
fi

set -e

echo -e "${GREEN}Populate DB${NC}"

cat ${ROOT_PATH}/../schema-migrator/migrations/director/*.up.sql | \
    docker exec -i ${POSTGRES_CONTAINER} psql -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" -d "${DB_NAME}"
cat ${ROOT_PATH}/../schema-migrator/seeds/director/*.sql | \
    docker exec -i ${POSTGRES_CONTAINER} psql -U "${DB_USER}" -h "${DB_HOST}" -p "${DB_PORT}" -d "${DB_NAME}"

if [[  ${SKIP_APP_START} ]]; then
        echo -e "${GREEN}Skipping starting application${NC}"
        while true
        do
            sleep 1
        done
fi

echo -e "${GREEN}Starting application${NC}"

APP_DB_USER=${DB_USER} \
APP_DB_PASSWORD=${DB_PWD} \
APP_DB_NAME=${DB_NAME} \
APP_CONFIGURATION_FILE=${ROOT_PATH}/hack/config-local.yaml \
APP_STATIC_USERS_SRC=${ROOT_PATH}/hack/static-users-local.yaml \
APP_STATIC_GROUPS_SRC=${ROOT_PATH}/hack/static-groups-local.yaml \
APP_OAUTH20_CLIENT_ENDPOINT="https://oauth2-admin.kyma.local/clients" \
APP_OAUTH20_PUBLIC_ACCESS_TOKEN_ENDPOINT="https://oauth2.kyma.local/oauth2/token" \
APP_ONE_TIME_TOKEN_URL="http://connector.not.configured.url/graphql" \
APP_CONNECTOR_URL="http://connector.not.configured.url/graphql" \
APP_LEGACY_CONNECTOR_URL="https://adapter-gateway.kyma.local/v1/applications/signingRequests/info" \
go run ${ROOT_PATH}/cmd/director/main.go
