class FieldListComponent < ViewComponent::Base
  def initialize(fields:)
    @fields = Array(fields)
  end

  def empty?
    @fields.empty?
  end

  def fields
    @fields
  end

  def required?(field)
    field.is_a?(Hash) && (field["required"] || field[:required])
  end

  def field_name(field)
    field["name"] || field[:name]
  end

  def field_type(field)
    field["type"] || field[:type] || "string"
  end

  def field_description(field)
    field["description"] || field[:description]
  end

  def field_values(field)
    field["values"] || field[:values]
  end
end
