module Infrastructure
  module Messaging
    # Espejo del envelope publicado/consumido por el resto del ecosistema. Ver
    # docs/event-catalog.md en rhm-database-infrastructure.
    Envelope = Struct.new(:id, :type, :version, :occurred_at, :producer, :data, keyword_init: true) do
      def self.parse(raw)
        new(
          id: raw.fetch('id'),
          type: raw.fetch('type'),
          version: raw.fetch('version'),
          occurred_at: raw.fetch('occurredAt'),
          producer: raw.fetch('producer'),
          data: raw.fetch('data')
        )
      end

      def to_json_payload
        {
          id: id,
          type: type,
          version: version,
          occurredAt: occurred_at,
          producer: producer,
          data: data,
        }
      end
    end
  end
end
