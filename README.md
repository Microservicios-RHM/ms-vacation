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

Añadido en el **Reto 5**:

- ✅ **Scheduler**: pasa los períodos a `EN_CURSO` y a `FINALIZADA` al llegar sus fechas, y publica
  `vacaciones.iniciadas` y `vacaciones.finalizadas`.
- ✅ `GET /vacaciones?estado=` para filtrar por estado, combinable con `empleadoId`.
- ✅ Al consumir `empleado.retirado`, cancela los períodos del empleado que aún no habían iniciado.
- ✅ `POST /vacaciones/{id}/forzar-inicio` y `forzar-fin`, endpoints de desarrollo para demostrar
  el ciclo sin esperar al cambio de día.
- ✅ OpenAPI con el esquema de seguridad `BearerAuth`.

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

SCHEDULER_ENABLED=true
SCHEDULER_INTERVAL_SECONDS=60
```

Las dos últimas gobiernan el scheduler del Reto 5. El intervalo es de un minuto en desarrollo para
poder observar las transiciones sin esperar; apagarlo con `SCHEDULER_ENABLED=false` deja el
servicio funcionando pero sin que ningún período cambie de estado por sí solo.

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
curl -i "http://localhost:8080/vacaciones?estado=PROGRAMADA"
curl -i "http://localhost:8080/vacaciones?empleadoId=E001&estado=CANCELADA"
curl -i http://localhost:8080/vacaciones
curl -i -X DELETE http://localhost:8080/vacaciones/V-2026-0042
```

Desde el Reto 5 todas estas peticiones requieren `Authorization: Bearer <token>`. Las de escritura
exigen además rol `ADMIN`; las de lectura las puede hacer cualquier usuario autenticado.

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

## Scheduler (Reto 5)

Hasta el Reto 4 este servicio quedaba a medias: registraba períodos y publicaba
`vacaciones.programadas`, pero nada ocurría cuando llegaba la fecha de inicio. La cuenta del
empleado nunca se desactivaba porque nada observaba el paso del tiempo.

Una tarea periódica hace ahora dos cosas:

1. Los períodos `PROGRAMADA` cuya `fechaInicio` ya llegó pasan a `EN_CURSO` → publica
   `vacaciones.iniciadas`.
2. Los períodos `EN_CURSO` cuya `fechaFin` ya pasó pasan a `FINALIZADA` → publica
   `vacaciones.finalizadas`.

| Aspecto | Valor |
|---|---|
| Mecanismo | Hilo de Ruby con intervalo (`app/infrastructure/scheduler.rb`) |
| Frecuencia | `SCHEDULER_INTERVAL_SECONDS`, 60 segundos por defecto |
| Interruptor | `SCHEDULER_ENABLED`, `true` por defecto |

Ruby no tiene un equivalente directo a `@Scheduled` de Spring. Se eligió un hilo simple antes que
una gema como `rufus-scheduler`: el Gemfile se mantiene mínimo y el comportamiento que hace falta
cabe en treinta líneas.

Dos detalles de implementación que no son evidentes:

**Las transiciones se resuelven con un único `UPDATE ... RETURNING`**, no leyendo primero y
actualizando después. Así la lectura y el cambio de estado son atómicos, y dos pasadas simultáneas
no pueden publicar el mismo evento dos veces: la segunda simplemente no encuentra filas que
cumplan la condición.

**Un fallo en una pasada no mata el hilo.** Si lo matara, el contenedor seguiría viéndose sano para
Docker pero ningún período volvería a transicionar en toda la vida del proceso, y nadie se
enteraría.

### Cómo demostrarlo sin esperar un día

El enunciado sugiere programar vacaciones con `fechaInicio = hoy` y `fechaFin = hoy`. Aquí **no
funciona**: la validación de `POST /vacaciones` exige que la fecha de fin sea posterior a la de
inicio. Esa regla viene del Reto 4, es correcta, y no se modificó.

Se eligió la tercera estrategia del enunciado: dos endpoints de desarrollo, protegidos con rol
`ADMIN` y marcados como tales en la documentación.

```bash
curl -i -X POST http://localhost:8080/vacaciones/V-2026-0042/forzar-inicio   -H "Authorization: Bearer <token ADMIN>"

curl -i -X POST http://localhost:8080/vacaciones/V-2026-0042/forzar-fin   -H "Authorization: Bearer <token ADMIN>"
```

Disparan exactamente la misma transición y el mismo evento que dispararía el paso del tiempo. No
son un atajo que salte reglas: si el período no está en el estado de origen correcto, responden
`409`.

### Limitación conocida

El hilo corre **dentro de cada instancia** del servicio. Mientras haya una sola, funciona.

Si `vacaciones-service` se escalara a N réplicas, las N ejecutarían el job y publicarían el mismo
evento N veces: N correos, N desactivaciones de cuenta. Hay dos defensas, complementarias:

1. **Deduplicación en el consumidor**, que ya existe: `auth-service` y `notificaciones-service`
   descartan el evento repetido por el `id` del envelope. Mitiga el daño, pero el trabajo duplicado
   igual se hizo.
2. **Coordinación en el productor**: garantizar que solo una instancia ejecute el job. Es lo que
   resuelve el Reto 31 con un lock distribuido en base de datos (ShedLock).

Este reto acepta la versión de instancia única. El Reto 11 usará esta limitación como caso de
estudio al escalar horizontalmente.

## Cancelación de períodos al retirar un empleado (Reto 5)

Antes, si a un empleado lo retiraban, sus vacaciones programadas quedaban ahí indefinidamente. Al
consumir `empleado.retirado` el servicio ahora pasa a `CANCELADA` los períodos de ese empleado.

**Solo los que están en `PROGRAMADA`.** Un período `EN_CURSO` se deja correr hasta `FINALIZADA`, y
eso es deliberado por dos razones:

- Unas vacaciones que ya empezaron ocurrieron de verdad. Cancelarlas las borraría del historial.
- Su `vacaciones.finalizadas` es justamente lo que `auth-service` necesita para cerrar el ciclo:
  al recibirlo comprueba que la cuenta quedó con baja permanente y **no** la reactiva. Si
  canceláramos el período en curso, ese evento nunca llegaría y el caso borde no podría
  demostrarse.

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

## Pruebas (Reto 6)

```bash
bundle install
bundle exec rspec                      # unitarias + integración, con reportes y umbral de cobertura
bundle exec rspec --tag ~integration   # solo unitarias: no necesitan Docker
```

| Reporte | Ruta | Formato |
|---|---|---|
| Resultados | `reports/junit.xml` | JUnit XML (`rspec_junit_formatter`) |
| Cobertura | `reports/coverage.xml` | Cobertura XML (`simplecov-cobertura`) |
| Cobertura navegable | `reports/index.html` | HTML de SimpleCov |

`bundle exec rspec` termina con código distinto de cero si una prueba falla **o** si la cobertura
de líneas cae por debajo del 70 % (`minimum_coverage` en `spec/coverage_helper.rb`). Cobertura
actual: 90,6 %.

### Qué cubren

- **Dominio** (`spec/domain`): `VacationPeriod#overlaps?` contra una tabla de 12 casos borde
  (idéntico, contenido, contiene, empieza/termina dentro, se toca por un día en cada extremo,
  adyacente, disjunto) más el cruce de año. La tabla vive en `spec/support/overlap_cases.rb`.
- **Aplicación** (`spec/application`): las cuatro validaciones de `ScheduleVacation` con sus bordes
  (fin igual a inicio, inicia hoy, inició ayer, solapamiento con `EN_CURSO`, ignorar `CANCELADA` y
  otros empleados, empleado retirado) y el **orden** en que se evalúan; `ForceVacationTransition`
  (el disparo manual que usa la suite BDD) con sus 409. Repositorio, registro de empleados y
  publicador son dobles en memoria; `DomainOverlapVacationRepository` delega el solapamiento en la
  regla de dominio para que el caso de uso no pruebe una copia de la regla escrita en el doble.
- **Integración** (`spec/integration`, etiqueta `:integration`): `VacationRepository` y
  `EmployeeRegistryRepository` contra un PostgreSQL 17 real. Valida migraciones idempotentes, el
  formato `V-AAAA-NNNN`, el `CHECK` de estados, la atomicidad de las transiciones del scheduler y
  —con **la misma tabla de 12 casos**— que la consulta de solapamiento en SQL coincida con la regla
  de dominio en Ruby.

### Decisiones

- **Estrategia de integración: contenedor desechable.** `spec/support/postgres_container.rb` hace
  lo mismo que Testcontainers con el CLI de Docker: arranca `postgres:17-alpine` (la imagen del
  Compose) en un puerto aleatorio, espera con polling a que acepte conexiones, y lo destruye al
  terminar. Se prefirió a una base embebida porque la regla de solapamiento está escrita también en
  SQL y solo el mismo motor la prueba de verdad; y a una instancia fija en el Compose porque no
  deja estado entre ejecuciones. Se descartó la gema `testcontainers-ruby` porque su cliente Docker
  no soporta el *named pipe* de Docker Desktop en Windows.
- **Qué no se prueba unitariamente** (excluido de la cobertura en `spec/coverage_helper.rb`):
  `bootstrap.rb` (raíz de composición), `logging.rb`, y los reintentos de conexión de
  `messaging/connection.rb` y `persistence/database.rb`. Son cableado sin reglas de negocio;
  probarlos inflaría el porcentaje sin aportar seguridad.
- **La trampa del 70 %.** Además de medir cobertura, se rompió la regla a propósito (`<=` por `<`
  en `overlaps?`): 4 pruebas fallaron, cada una nombrando el caso borde exacto. Las aserciones
  comprueban códigos de error, estados resultantes y eventos publicados (o su ausencia), no solo
  que el código "corra".

No existe un cálculo de días de vacaciones en el servicio, así que no hay prueba para él.
