module Infrastructure
  module Persistence
    # Réplica local mínima de empleados válidos (empleado_id -> activo), construida a partir de
    # empleado.creado/empleado.retirado. Ver README para la justificación de esta estrategia
    # frente a la alternativa de consultar empleados-service por REST.
    class EmployeeRegistryRepository
      def initialize(pool)
        @pool = pool
      end

      def valid?(empleado_id)
        @pool.with do |conn|
          result = conn.exec_params(
            'SELECT activo FROM empleados_validos WHERE empleado_id = $1', [empleado_id]
          )
          result.ntuples.positive? && result[0]['activo'] == 't'
        end
      end

      # Dedup + upsert en una transacción — mismo patrón que en ms-employees/ms-notifications/
      # ms-profiles. Idempotente: un empleado.creado repetido para el mismo empleado_id (no
      # debería ocurrir, pero el UPSERT lo tolera) no produce error.
      def mark_valid_if_new(event_id, empleado_id)
        @pool.with do |conn|
          conn.transaction do |tx|
            inserted = tx.exec_params(
              'INSERT INTO eventos_procesados (id) VALUES ($1) ON CONFLICT DO NOTHING RETURNING id',
              [event_id]
            )
            next false if inserted.ntuples.zero?

            tx.exec_params(
              <<~SQL, [empleado_id]
                INSERT INTO empleados_validos (empleado_id, activo)
                VALUES ($1, true)
                ON CONFLICT (empleado_id) DO UPDATE SET activo = true, actualizado_en = NOW()
              SQL
            )
            true
          end
        end
      end

      # Retorna [was_new, found]. found = false si empleado.retirado llegó para un empleado_id
      # que nunca pasó por empleado.creado (no debería ocurrir en operación normal).
      def mark_invalid_if_new(event_id, empleado_id)
        @pool.with do |conn|
          conn.transaction do |tx|
            inserted = tx.exec_params(
              'INSERT INTO eventos_procesados (id) VALUES ($1) ON CONFLICT DO NOTHING RETURNING id',
              [event_id]
            )
            next [false, false] if inserted.ntuples.zero?

            result = tx.exec_params(
              'UPDATE empleados_validos SET activo = false, actualizado_en = NOW() WHERE empleado_id = $1',
              [empleado_id]
            )
            [true, result.cmd_tuples.positive?]
          end
        end
      end
    end
  end
end
