# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Opensop::DemoMode.enabled?
  # Demo deployment: load ONLY the curated examples from processes/examples/.
  # Do NOT use the broad Registry.load_all glob here — that would pick up
  # private subdirectories (processes/coba/, etc.) and pollute the public
  # demo catalog. Demo::SeedLoader is scoped to processes/examples/ and also
  # validates the demo API token.
  result = Demo::SeedLoader.call
  puts "[seed] demo mode: #{result.processes_loaded} example process(es) ready, token_configured=#{result.token_configured}"
else
  # Standard deployment: load all process definitions from processes/**/*.sop.yaml.
  # Forks drop their private processes/ subdirectory here and they auto-load.
  loaded = Opensop::Registry.load_all
  puts "[seed] loaded #{loaded.size} OpenSOP process definition(s)"
  loaded.each do |record|
    puts "[seed]   - #{record.name} v#{record.version} (status: #{record.status})"
  end
end
