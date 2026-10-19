require_relative '../../app/domain/vacation_period'
require_relative '../support/overlap_cases'

# Regla pura de solapamiento sobre dos rangos de fechas cerrados [inicio, fin]. Se prueba como una
# tabla de casos borde: es la lógica más fácil de romper con un refactor (un < en lugar de <=) y la
# más lenta de detectar si solo se probara por HTTP.
RSpec.describe Domain::VacationPeriod do
  let(:existente) do
    described_class.new(
      id: 'V-2026-0001', empleado_id: 'E001',
      fecha_inicio: OverlapCases::EXISTING_START, fecha_fin: OverlapCases::EXISTING_END,
      estado: 'PROGRAMADA'
    )
  end

  describe '#overlaps?' do
    OverlapCases::TABLE.each do |descripcion, inicio, fin, esperado|
      it "#{esperado ? 'detecta' : 'no detecta'} solapamiento cuando el nuevo período #{descripcion}" do
        expect(existente.overlaps?(inicio, fin)).to be(esperado)
      end
    end

    it 'compara correctamente rangos que cruzan el cambio de año' do
      diciembre = described_class.new(fecha_inicio: '2026-12-28', fecha_fin: '2027-01-03')

      expect(diciembre.overlaps?('2027-01-03', '2027-01-10')).to be(true)
      expect(diciembre.overlaps?('2027-01-04', '2027-01-10')).to be(false)
    end
  end

  describe '#to_h' do
    it 'expone el período con los nombres de campo del contrato HTTP' do
      expect(existente.to_h).to include(
        id: 'V-2026-0001', empleadoId: 'E001',
        fechaInicio: '2026-07-10', fechaFin: '2026-07-20', estado: 'PROGRAMADA'
      )
    end
  end
end
