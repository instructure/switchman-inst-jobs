#!/usr/bin/env bash

set -ex

export COMPOSE_FILE="docker-compose.yml"

function cleanup() {
  exit_code=$?
  set +e
  docker cp coverage:/app/coverage .
  docker-compose kill
  docker-compose rm -f
  exit $exit_code
}
trap cleanup INT TERM EXIT

docker-compose pull postgres
docker-compose up -d postgres
docker-compose build --pull app
docker-compose run --rm app /bin/bash -l -c \
  "rvm-exec 2.4 bundle exec rubocop --fail-level autocorrect"
docker-compose run --name coverage app $@
