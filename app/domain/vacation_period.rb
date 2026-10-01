module Domain
  VacationPeriod = Struct.new(
    :id, :empleado_id, :fecha_inicio, :fecha_fin, :estado, :fecha_creacion,
    keyword_init: true
  ) do
    def to_h
      {
        id: id,
        empleadoId: empleado_id,
        fechaInicio: fecha_inicio,
        fechaFin: fecha_fin,
        estado: estado,
        fechaCreacion: fecha_creacion,
      }
    end

    def overlaps?(otro_inicio, otro_fin)
      fecha_inicio <= otro_fin && fecha_fin >= otro_inicio
    end
  end
end
