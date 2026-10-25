# Tabla única de casos borde de solapamiento contra el período existente 2026-07-10 .. 2026-07-20.
# La usan dos suites: la unitaria (VacationPeriod#overlaps?, regla en Ruby) y la de integración
# (VacationRepository#find_overlapping, la misma regla escrita en SQL). Si ambas pasan con la misma
# tabla, el dominio y la consulta no pueden divergir sin que una prueba lo detecte.
module OverlapCases
  EXISTING_START = '2026-07-10'.freeze
  EXISTING_END = '2026-07-20'.freeze

  # [descripción, nuevo inicio, nuevo fin, ¿se solapa?]
  TABLE = [
    ['es idéntico al existente',                    '2026-07-10', '2026-07-20', true],
    ['empieza dentro y termina después',            '2026-07-15', '2026-07-25', true],
    ['empieza antes y termina dentro',              '2026-07-05', '2026-07-15', true],
    ['contiene por completo al existente',          '2026-07-05', '2026-07-25', true],
    ['queda contenido dentro del existente',        '2026-07-12', '2026-07-18', true],
    ['empieza el mismo día en que termina el otro', '2026-07-20', '2026-07-25', true],
    ['termina el mismo día en que empieza el otro', '2026-07-01', '2026-07-10', true],
    ['dura un solo día dentro del existente',       '2026-07-15', '2026-07-15', true],
    ['empieza el día siguiente al fin del otro',    '2026-07-21', '2026-07-25', false],
    ['termina el día anterior al inicio del otro',  '2026-07-01', '2026-07-09', false],
    ['queda completamente antes',                   '2026-06-01', '2026-06-15', false],
    ['queda completamente después',                 '2026-08-01', '2026-08-15', false],
  ].freeze
end
