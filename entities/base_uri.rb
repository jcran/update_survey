module UpdateSurvey
module Entity
class BaseUri < Intrigue::Model::Entity

  def self.metadata
    {
      :name => "BaseUri",
      :description => "A Website",
      :user_creatable => false
    }
  end

  def validate_entity
    name =~ /^https?:\w.*$/
  end

  def detail_string
    "Server: #{details["server_fingerprint"].to_a.join("; ")} | " +
    "App: #{details["app_fingerprint"].to_a.join("; ")} | " +
    "Title: #{details["title"]}"
  end

  def enrichment_tasks
    ["enrich/base_uri", "enrich/base_uri_stack_fingerprint"]
  end

end
end
end
