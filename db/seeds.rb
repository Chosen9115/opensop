# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Load all OpenSOP process definitions from the `processes/` directory.
loaded = Opensop::Registry.load_all
puts "[seed] loaded #{loaded.size} OpenSOP process definition(s)"
loaded.each do |record|
  puts "[seed]   - #{record.name} v#{record.version} (status: #{record.status})"
end
