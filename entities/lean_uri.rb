module Intrigue
module Entity
class LeanUri < Intrigue::Model::Entity

  def self.metadata
    {
      :name => "LeanUri",
      :description => "A Website or Webpage - no browser session",
      :user_creatable => false
    }
  end

  def validate_entity
    name =~ /^\w.*$/
  end

  def detail_string
    "Server: #{details["server_fingerprint"].to_a.join("; ")} | " +
    "App: #{details["app_fingerprint"].to_a.join("; ")} | " +
    "Title: #{details["title"]}"
  end

  def enrichment_tasks
    ["enrich/lean_uri", "enrich/lean_uri_stack_fingerprint"]
  end

end
end
end
