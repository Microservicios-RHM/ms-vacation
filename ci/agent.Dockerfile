# Agente efímero de las etapas Build y Test del Jenkinsfile. Misma base que el Dockerfile del
# servicio (ruby:3.4-alpine + toolchain para gemas nativas) más el cliente Docker, porque las pruebas
# de integración levantan su propio PostgreSQL con `docker run` (spec/support/postgres_container.rb).
FROM ruby:3.4-alpine

RUN apk add --no-cache build-base postgresql-dev

COPY --from=docker:29-cli /usr/local/bin/docker /usr/local/bin/docker

# Sin root: usuario con el mismo uid/gid que Jenkins (1000), que es con el que el pipeline ejecuta el
# agente. Sin home propio (-H): el Jenkinsfile usa HOME=/tmp.
RUN addgroup -S -g 1000 ci && adduser -S -D -H -u 1000 -G ci -h /tmp ci
USER ci
