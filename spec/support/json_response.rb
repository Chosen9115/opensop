module JsonResponse
  def json
    JSON.parse(response.body, symbolize_names: true)
  end
end

RSpec.configure do |config|
  config.include JsonResponse, type: :request
end
