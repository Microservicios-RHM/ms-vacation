class FakeEmployeeRegistry
  attr_accessor :already_processed

  def initialize
    @valid = {}
    @already_processed = false
  end

  def valid?(empleado_id)
    @valid[empleado_id] == true
  end

  def mark_valid_if_new(_event_id, empleado_id)
    return false if @already_processed

    @valid[empleado_id] = true
    true
  end

  def mark_invalid_if_new(_event_id, empleado_id)
    return [false, false] if @already_processed

    found = @valid.key?(empleado_id)
    @valid[empleado_id] = false if found
    [true, found]
  end
end
