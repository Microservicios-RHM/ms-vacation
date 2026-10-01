module Infrastructure
  module Persistence
    # Espejo de migration.runner.ts (ms-employees), migrations.py (ms-notifications) y
    # migrations.go (ms-profiles): versionadas, idempotentes, con advisory lock.
    module Migrations
      ADVISORY_LOCK_ID = 553_219

      MIGRATIONS = [
        {
          version: 1,
          name: 'create_vacation_tables',
          sql: <<~SQL,
            CREATE TABLE empleados_validos (
              empleado_id VARCHAR(50) PRIMARY KEY,
              activo BOOLEAN NOT NULL DEFAULT TRUE,
              actualizado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            CREATE TABLE vacaciones (
              id VARCHAR(20) PRIMARY KEY,
              empleado_id VARCHAR(50) NOT NULL,
              fecha_inicio DATE NOT NULL,
              fecha_fin DATE NOT NULL,
              estado VARCHAR(20) NOT NULL DEFAULT 'PROGRAMADA'
                CHECK (estado IN ('PROGRAMADA', 'EN_CURSO', 'FINALIZADA', 'CANCELADA')),
              fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            CREATE INDEX vacaciones_empleado_id_idx ON vacaciones (empleado_id);
            CREATE INDEX vacaciones_estado_idx ON vacaciones (estado);

            CREATE TABLE eventos_procesados (
              id UUID PRIMARY KEY,
              procesado_en TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );

            CREATE SEQUENCE vacaciones_id_seq START 1;
          SQL
        },
      ].freeze

      def self.run(pool)
        applied = []
        pool.with do |conn|
          conn.exec_params('SELECT pg_advisory_lock($1)', [ADVISORY_LOCK_ID])
          begin
            conn.exec(<<~SQL)
              CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
              )
            SQL

            MIGRATIONS.each do |migration|
              exists = conn.exec_params(
                'SELECT 1 FROM schema_migrations WHERE version = $1', [migration[:version]]
              ).ntuples.positive?
              next if exists

              conn.transaction do |tx|
                tx.exec(migration[:sql])
                tx.exec_params(
                  'INSERT INTO schema_migrations (version, name) VALUES ($1, $2)',
                  [migration[:version], migration[:name]]
                )
              end
              applied << "#{migration[:version]} - #{migration[:name]}"
            end
          ensure
            conn.exec_params('SELECT pg_advisory_unlock($1)', [ADVISORY_LOCK_ID])
          end
        end
        applied
      end
    end
  end
end
