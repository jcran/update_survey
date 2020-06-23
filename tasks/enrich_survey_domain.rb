module Intrigue
module Task
module Enrich
class SurveyDomain < Intrigue::Task::BaseTask

  include Intrigue::Task::Dns

  def self.metadata
    {
      :name => "enrich/survey_domain",
      :pretty_name => "Enrich Domain",
      :authors => ["jcran"],
      :description => "Fills in details for a Domain",
      :references => [],
      :allowed_types => ["SurveyDomain"],
      :type => "enrichment",
      :passive => true,
      :example_entities => [
        {"type" => "SurveyDomain", "details" => {"name" => "intrigue.io"}}],
      :allowed_options => [],
      :created_types => []
    }
  end

  def run

    d = _get_entity_name

    e = _create_entity "Uri", { "name" => "http://#{d}" }
    _create_entity "Uri", { "name" => "https://#{d}" }, e 
    _create_entity "Uri", { "name" => "http://www.#{d}" }, e
    _create_entity "Uri", { "name" => "https://www.#{d}" }, e

  end

end
end
end
end