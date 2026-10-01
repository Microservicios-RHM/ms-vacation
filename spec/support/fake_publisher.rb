class FakePublisher
  attr_reader :published

  def initialize
    @published = []
  end

  def publish(type:, data:)
    @published << { type: type, data: data }
  end
end
