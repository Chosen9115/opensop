module ProcessDefinitionBuilder
  # Build a valid process definition hash without having to hand-write
  # the full structure in every spec.
  #
  # Common overrides:
  #   name:    String — process name
  #   steps:   Array — step mappings
  #   inputs:  Array — input field specs (defaults to a single required "alpha")
  #   outputs: Array — output field specs
  def build_process_definition(overrides = {})
    steps   = overrides[:steps]   || []
    inputs  = overrides[:inputs]  || [ { "name" => "alpha", "type" => "string", "required" => true } ]
    outputs = overrides[:outputs] || [ { "name" => "result", "type" => "string" } ]

    process_block = {
      "name"        => overrides[:name] || "test-proc",
      "version"     => overrides[:version] || "1.0",
      "description" => overrides[:description] || "Test process",
      "inputs"      => inputs,
      "outputs"     => outputs,
      "steps"       => steps
    }

    {
      "opensop" => "0.1",
      "process" => process_block
    }
  end

  # Build a process record whose `definition` matches the supplied overrides.
  def build_process(overrides = {})
    definition = build_process_definition(overrides)
    process_block = definition["process"]
    create(:sop_process,
           name: process_block["name"],
           version: process_block["version"],
           description: process_block["description"],
           definition: definition)
  end
end

RSpec.configure do |config|
  config.include ProcessDefinitionBuilder
end
