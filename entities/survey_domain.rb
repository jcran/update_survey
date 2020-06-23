module Intrigue
module Entity
module Survey
class Domain < Intrigue::Core::Model::Entity

  def self.metadata
    {
      :name => "SurveyDomain",
      :description => "A Domain",
      :user_creatable => false
    }
  end

  def validate_entity
    name =~ dns_regex
  end

  def detail_string
    return "" unless details["resolutions"]
    details["resolutions"].each.group_by{|k| 
      k["response_type"] }.map{|k,v| "#{k}: #{v.length}"}.join(" | ")
  end

  def enrichment_tasks
    ["enrich/survey_domain"]
  end

end
end
end
end