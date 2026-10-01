# Microservicio de vacaciones

Servicio construido en Ruby (Sinatra, sin ORM), con arquitectura hexagonal equivalente al resto
del ecosistema. Es el único de los tres servicios nuevos del Reto 4 que combina los tres roles:
consume eventos (para su réplica local de empleados válidos), expone REST (CRUD de períodos), y
publica eventos propios (`vacaciones.programadas`).

Forma parte del ecosistema RHM (Reto 4). El contrato de eventos está en `docs/event-catalog.md` del
repositorio [rhm-database-infrastructure](https://github.com/Microservicios-RHM/rhm-database-infrastructure).

## Estado

- ✅ `POST /vacaciones` con las 4 validaciones exigidas por el enunciado, en orden: fechas
  incoherentes, fechas en el pasado, solapamiento (incluye el período en conflicto en la
  respuesta), empleado inexistente.
- ✅ `GET /vacaciones/{id}`, `GET /vacaciones?empleadoId=`, `GET /vacaciones`, `DELETE
  /vacaciones/{id}` (cancela solo si el período aún no inició).
- ✅ Publica `vacaciones.programadas` tras programar exitosamente.
- ✅ Consume `empleado.creado`/`empleado.retirado` para mantener su réplica local de empleados
  válidos (ver justificación de la decisión técnica más abajo), con deduplicación.
- ✅ OpenAPI 3.1 + Swagger UI (`/vacaciones/openapi.json`, `/vacaciones/docs`).
- ✅ Registrado en el API Gateway: `http://localhost:8080/vacaciones`, **incluida la documentación
  interactiva** en `http://localhost:8080/vacaciones/docs`.

Con este servicio completo, el Reto 4 queda terminado: los 4 eventos del catálogo tienen productor
y los consumidores correspondientes, y los 5 servicios están detrás del Gateway.

## Decisión técnica: validación de existencia del empleado

El enunciado pide justificar explícitamente esta decisión. Dos opciones:

- **(a) Consulta síncrona REST** a `empleados-service` en cada `POST /vacaciones`. Más simple de
  razonar (una sola fuente de verdad, sin duplicación de datos), pero acopla la disponibilidad de
  `vacaciones-service` a la de `empleados-service`: si ese servicio está caído o lento, programar
  vacaciones falla aunque el dato que realmente se necesita (¿existe este empleado?) ya se conoce
  desde hace rato.
- **(b) Réplica local por eventos** — la elegida. `vacaciones-service` consume `empleado.creado` y
  `empleado.retirado`, y mantiene su propia tabla mínima `empleados_validos(empleado_id, activo)`.
  `POST /vacaciones` consulta esa tabla local, nunca la red.

Se eligió **(b)** por consistencia con el resto del ecosistema — `notificaciones-service` ya
resuelve el mismo tipo de problema (destinatario de `vacaciones.programadas`) con un directorio
local en vez de una llamada REST — y porque es la elección que prioriza **disponibilidad sobre
consistencia inmediata**: `vacaciones-service` puede seguir programando vacaciones aunque
`empleados-service` esté caído, a costa de que su copia de "empleados válidos" pueda quedar
desactualizada por el tiempo que tarde el evento en propagarse (normalmente milisegundos). Esa
inconsistencia eventual es aceptable para este dominio; la alternativa —que toda la plataforma de
vacaciones dependa de la disponibilidad de otro servicio para una operación de escritura— no lo es.

La contrapartida real, documentada sin ocultarla: si `vacaciones-service` arranca por primera vez
con una cola vacía (por ejemplo, se creó después de que ya existieran empleados y aún no se
republicó su historial), su registro local estará incompleto hasta que lleguen altas o
actualizaciones nuevas. Este reto no requiere un mecanismo de "replay" del historial completo de
eventos (eso excede el alcance); se documenta como limitación conocida.

## Requisitos

- Ruby 3.4 (`Dockerfile` usa `ruby:3.4-alpine` para build y runtime) y las cabeceras de desarrollo
  del sistema si vas a instalar gems con extensiones nativas localmente (`ruby-devel`/`build-base`
  o equivalente de tu distro; `bunny` depende transitivamente de `sorted_set`/`rbtree`, que sí
  compila una extensión nativa).
- Docker y Docker Compose para ejecutar el servicio real — igual que el resto del ecosistema, la
  infraestructura no publica puertos de bases de datos ni de RabbitMQ al host.

## Configuración local (tooling, no ejecución)

```bash
bundle install
cp .env.example .env
bundle exec rspec
```

Los tests usan dobles de prueba (repositorios en memoria), no una conexión real a PostgreSQL ni a
RabbitMQ. Para correr el servicio contra las dependencias reales, el único flujo soportado es
Docker Compose desde `rhm-database-infrastructure`:

```bash
cd ../rhm-database-infrastructure
docker compose up --build
```

Dentro de Docker, PostgreSQL se resuelve como `database-vacaciones:5432` y RabbitMQ como
`message-broker:5672`; ninguno de los dos publica su puerto al host para este servicio.

## Variables de entorno

`.env.example` documenta todas las variables. Las relevantes:

```dotenv
DB_HOST=database-vacaciones
DB_PORT=5432
DB_NAME=vacations_db
DB_USER=vacations_service
DB_PASSWORD=change_vacations_password

BROKER_URL=amqp://admin:admin@message-broker:5672
BROKER_EXCHANGE=rhm.events
BROKER_QUEUE=vacaciones.queue
```

La aplicación valida la configuración al arrancar (`app/infrastructure/config.rb`) y falla
inmediatamente si falta una variable requerida (`DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`BROKER_URL`) o si `BROKER_URL` no tiene el esquema `amqp://`/`amqps://`.

## API

Envelope estándar del ecosistema, JSON en camelCase.

```bash
curl -i -X POST http://localhost:8080/vacaciones \
  -H "Content-Type: application/json" \
  -d '{"empleadoId":"E001","fechaInicio":"2026-06-15","fechaFin":"2026-06-30"}'

curl -i http://localhost:8080/vacaciones/V-2026-0042
curl -i "http://localhost:8080/vacaciones?empleadoId=E001"
curl -i http://localhost:8080/vacaciones
curl -i -X DELETE http://localhost:8080/vacaciones/V-2026-0042
```

Respuestas de error relevantes:

| Código | Status | Causa |
|---|---:|---|
| `INVALID_DATE_RANGE` | 400 | `fechaFin` no es posterior a `fechaInicio`. |
| `DATE_IN_THE_PAST` | 400 | `fechaInicio` es anterior a hoy. |
| `VACATION_OVERLAP` | 400 | Ya existe un período `PROGRAMADA`/`EN_CURSO` que se cruza con el rango. La respuesta incluye `error.conflictingPeriod` con el período existente completo. |
| `EMPLOYEE_NOT_FOUND` | 400 | El `empleadoId` no está en la réplica local de empleados válidos (no existe, o fue retirado). |
| `VACATION_NOT_FOUND` | 404 | El `id` no corresponde a ningún período. |
| `VACATION_ALREADY_STARTED` | 400 | `DELETE` sobre un período cuyo `fechaInicio` ya llegó, o que no está `PROGRAMADA`. |
| `VALIDATION_ERROR` | 400 | Campos faltantes o con formato inválido (`error.details` como en el resto del ecosistema). |

Documentación interactiva — montada bajo `/vacaciones` (no en la raíz) para vivir detrás del
Gateway sin que este necesite ninguna regla especial, ya que `/vacaciones/*` ya se proxea sin
reescritura de ruta:

```text
Swagger UI:     http://localhost:8080/vacaciones/docs
OpenAPI JSON:   http://localhost:8080/vacaciones/openapi.json
```

## Arquitectura

```text
config.ru                                Punto de entrada Rack
app/
├── bootstrap.rb                         Raíz de composición
├── domain/
│   ├── vacation_period.rb               Entidad (Struct)
│   ├── errors.rb                        AppError (status, code, details, conflicting_period)
│   └── error_codes.rb                   Catálogo de códigos
├── application/
│   ├── schedule_vacation.rb             POST /vacaciones — las 4 validaciones + publish
│   ├── get_vacation.rb / list_vacations.rb / cancel_vacation.rb
│   ├── register_valid_employee.rb       empleado.creado → réplica local
│   └── invalidate_employee.rb           empleado.retirado → réplica local
└── infrastructure/
    ├── config.rb / logging.rb
    ├── http/
    │   ├── app.rb                       Sinatra::Base, rutas, manejo de errores
    │   ├── response_helpers.rb          Envelope success/error del ecosistema
    │   ├── openapi.json / docs.html     Documentación (servidos como archivos estáticos)
    ├── messaging/
    │   ├── envelope.rb
    │   ├── connection.rb                Conexión AMQP compartida (dependencia dura)
    │   ├── consumer.rb                  empleado.creado/retirado → réplica local
    │   └── publisher.rb                 vacaciones.programadas (best-effort, nunca lanza)
    └── persistence/
        ├── database.rb                  ConnectionPool sobre pg, con reintentos
        ├── migrations.rb                Versionadas e idempotentes
        ├── vacation_repository.rb
        └── employee_registry_repository.rb
```

Los casos de uso dependen de los repositorios por su interfaz implícita (duck typing, como es
idiomático en Ruby), no de `pg` directamente. `bootstrap.rb` construye las implementaciones
Postgres/AMQP concretas y las inyecta — misma raíz de composición que `server.ts`, `main.py` y
`main.go` en los otros tres servicios.

### Broker: dependencia dura para consumir, best-effort para publicar

`Connection` es una dependencia dura (si no conecta tras los reintentos, el proceso no arranca) —
la réplica local de empleados es indispensable para que `POST /vacaciones` funcione en absoluto.
`Publisher`, en cambio, nunca lanza: un fallo al publicar `vacaciones.programadas` no debe revertir
un período ya persistido ni afectar la respuesta HTTP — mismo contrato que `EventPublisher` en
`ms-employees`, porque publicar es un efecto secundario de una operación REST, no su razón de ser.

### Deduplicación

`EmployeeRegistryRepository#mark_valid_if_new` / `#mark_invalid_if_new` siguen el mismo patrón
atómico (`INSERT ... ON CONFLICT DO NOTHING RETURNING id` + efecto, una transacción) que el resto
del ecosistema. **Verificado**: se republicó manualmente el mismo mensaje `vacaciones.programadas`
(mismo `id` de envelope) vía la API de administración de RabbitMQ; `notificaciones-service` (el
consumidor de ese evento) registró `"Duplicate event ignored"` y no generó una segunda
notificación.

## Persistencia

Base de datos propia (`vacations_db`, PostgreSQL 17). La migración `create_vacation_tables` crea:

- `vacaciones` (`id` con formato `V-<año>-<secuencial>`, `empleado_id`, `fecha_inicio`,
  `fecha_fin`, `estado` con `CHECK` en `PROGRAMADA`/`EN_CURSO`/`FINALIZADA`/`CANCELADA`,
  `fecha_creacion`), con índices sobre `empleado_id` y `estado`.
- `empleados_validos` (`empleado_id`, `activo`) — la réplica local.
- `eventos_procesados` (`id`, `procesado_en`) — deduplicación.
- Secuencia `vacaciones_id_seq` para el identificador legible.

`EN_CURSO`/`FINALIZADA` existen en el `CHECK` porque son parte del ciclo de vida completo del
dominio, pero ningún código de este reto los asigna — la transición automática por fecha
(`PROGRAMADA` → `EN_CURSO`) es del Reto 5 (scheduler). Por eso `CancelVacation` decide "¿ya
inició?" comparando `fechaInicio` contra la fecha actual, no solo mirando `estado`.

## Salud

```bash
docker exec vacaciones-service wget -qO- http://127.0.0.1:8080/health
```

`/health` responde el mismo envelope que el resto del ecosistema:
`{"success": true, "message": "Servicio disponible", "data": {"status": "UP"}}`.
