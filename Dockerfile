# Se fija Alpine explícitamente: `ruby:3.4-alpine` es una etiqueta flotante y la versión 3.24
# presenta errores de extracción de GCC en algunos Docker Desktop. Alpine 3.21 fue validado con
# las dependencias nativas de pg y hace la imagen reproducible.
FROM ruby:3.4-alpine3.24 AS build
WORKDIR /app

RUN apk add --no-cache build-base postgresql-dev

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'test' && bundle install

FROM ruby:3.4-alpine3.24
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
RUN apk add --no-cache libpq

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock ./
COPY app ./app
COPY config.ru ./

USER app
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health || exit 1

CMD ["sh", "-c", "bundle exec puma -p ${PORT:-8080} -e production config.ru"]
