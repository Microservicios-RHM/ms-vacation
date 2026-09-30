require 'time'
require_relative '../../domain/vacation_period'

module Infrastructure
  module Persistence
    class VacationRepository
      COLUMNS = 'id, empleado_id, fecha_inicio, fecha_fin, estado, fecha_creacion'.freeze

      def initialize(pool)
        @pool = pool
      end

      def next_id
        @pool.with do |conn|
          seq = conn.exec("SELECT nextval('vacaciones_id_seq') AS seq")[0]['seq']
          format('V-%<year>d-%<seq>04d', year: Time.now.year, seq: seq.to_i)
        end
      end

      # Un período PROGRAMADA o EN_CURSO existente cuyo rango se cruza con [fecha_inicio,
      # fecha_fin]. Las fechas viajan como texto ISO (YYYY-MM-DD): comparan correctamente como
      # strings, así que no hace falta parsear a Date para esta consulta (Postgres sí las compara
      # como DATE nativamente).
      def find_overlapping(empleado_id, fecha_inicio, fecha_fin)
        @pool.with do |conn|
          result = conn.exec_params(
            <<~SQL, [empleado_id, fecha_inicio, fecha_fin]
              SELECT #{COLUMNS} FROM vacaciones
               WHERE empleado_id = $1
                 AND estado IN ('PROGRAMADA', 'EN_CURSO')
                 AND fecha_inicio <= $3
                 AND fecha_fin >= $2
               LIMIT 1
            SQL
          )
          result.ntuples.positive? ? to_domain(result[0]) : nil
        end
      end

      def save(period)
        @pool.with do |conn|
          result = conn.exec_params(
            <<~SQL, [period.id, period.empleado_id, period.fecha_inicio, period.fecha_fin]
              INSERT INTO vacaciones (id, empleado_id, fecha_inicio, fecha_fin, estado, fecha_creacion)
              VALUES ($1, $2, $3, $4, 'PROGRAMADA', NOW())
              RETURNING #{COLUMNS}
            SQL
          )
          to_domain(result[0])
        end
      end

      def find_by_id(id)
        @pool.with do |conn|
          result = conn.exec_params("SELECT #{COLUMNS} FROM vacaciones WHERE id = $1", [id])
          result.ntuples.positive? ? to_domain(result[0]) : nil
        end
      end

      def list_all
        @pool.with do |conn|
          result = conn.exec("SELECT #{COLUMNS} FROM vacaciones ORDER BY fecha_creacion DESC")
          result.map { |row| to_domain(row) }
        end
      end

      def list_by_employee(empleado_id)
        @pool.with do |conn|
          result = conn.exec_params(
            "SELECT #{COLUMNS} FROM vacaciones WHERE empleado_id = $1 ORDER BY fecha_creacion DESC",
            [empleado_id]
          )
          result.map { |row| to_domain(row) }
        end
      end

      # Solo transiciona si el estado actual sigue siendo PROGRAMADA (defensivo contra una
      # carrera con otra cancelación concurrente). Retorna nil si no había nada que cancelar.
      def cancel(id)
        @pool.with do |conn|
          result = conn.exec_params(
            <<~SQL, [id]
              UPDATE vacaciones SET estado = 'CANCELADA'
               WHERE id = $1 AND estado = 'PROGRAMADA'
              RETURNING #{COLUMNS}
            SQL
          )
          result.ntuples.positive? ? to_domain(result[0]) : nil
        end
      end

      private

      def to_domain(row)
        Domain::VacationPeriod.new(
          id: row['id'],
          empleado_id: row['empleado_id'],
          fecha_inicio: row['fecha_inicio'],
          fecha_fin: row['fecha_fin'],
          estado: row['estado'],
          fecha_creacion: Time.parse(row['fecha_creacion']).utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')
        )
      end
    end
  end
end
