module UpdateSurvey
module Task
class EnrichBaseUri < BaseTask
  include Intrigue::Task::Web
  include Intrigue::Task::Browser

  def self.metadata
    {
      :name => "enrich/base_uri",
      :pretty_name => "Enrich A BaseUri",
      :authors => ["jcran"],
      :description => "",
      :references => [],
      :type => "enrichment",
      :passive => false,
      :allowed_types => ["BaseUri"],
      :example_entities => [{"type" => "BaseUri", "details" => {"name" => "https://intrigue.io"}}],
      :allowed_options => [],
      :created_types => []
    }
  end

  def run
    super

    uri = _get_entity_name

    # Grab the full response
    response = http_request :get, uri

    unless response && response.body
      _log_error "Unable to receive a response for #{uri}, bailing"
      return
    end

    response_data = response.body.sanitize_unicode
    response_data_hash = Digest::SHA256.base64digest(response_data) if response_data

    # we can check the existing response, so send that
    api_enabled = check_api_endpoint(response)

    # we can check the existing response, so send that
    contains_forms = check_forms(response_data)

    # we'll need to make another request
    verbs_enabled = check_options_endpoint(uri)

    # grab all script_references
    script_references = response_data.scan(/<script.*?src=["|'](.*?)["|']/).map{|x| x.first if x }

    # we'll need to make another request
    #trace_enabled = check_trace_endpoint(uri)

    # we'll need to make another request
    #webdav_enabled = check_webdav_endpoint(uri)

    new_details = @entity.details.merge({
      #"api_endpoint" => api_enabled,
      #"trace" => trace_enabled,
      #"webdav" => webdav_enabled,
      "code" => response.code,
      "title" => response.body[/<title>(.*)<\/title>/,1],
      "verbs" => verbs_enabled,
      "scripts" => script_references,
      "forms" => contains_forms,
      "response_data_hash" => response_data_hash,
      #"hidden_response_data" => response_data
    })

    # Set the details, and make sure raw response data is a hidden (not searchable) detail
    @entity.set_details(new_details)

    # Check for other entities with this same response hash
    #if response_data_hash
    #  Intrigue::Model::Entity.scope_by_project_and_type_and_detail_value(@entity.project.name,"Uri","response_data_hash", response_data_hash).each do |e|
    #    _log "Checking for Uri with detail: 'response_data_hash' == #{response_data_hash}"
    #    next if @entity.id == e.id
    #
    #    _log "Attaching entity: #{e} to #{@entity}"
    #    @entity.alias e
    #    @entity.save
    #  end
    #end

    ###############################################
    ## Library fingerprinting and Screenshotting ##
    ###############################################

    # create a capybara session and browse to our uri
    #session = create_browser_session(uri)

    # Capture versions of common javascript libs
    #
    # get existing software details (in case this is a second run)
    #libraries = @entity.get_detail("libraries") || []
    # run the version checking scripts in our session (See lib/helpers/browser)
    #libraries = gather_javascript_libraries(session, libraries)

    # set the new details
    #@entity.set_detail("libraries", libraries)

    # capture a screenshot and save it as a detail
    #base64_screenshot_data = capture_screenshot(session)
    #@entity.set_detail("hidden_screenshot_contents",base64_screenshot_data)

    _finalize_enrichment
  end

  def check_options_endpoint(uri)
    response = http_request(:options, uri)
    (response["allow"] || response["Allow"]) if response
  end

  def check_trace_endpoint(uri)
    response = http_request :trace, uri # todo... make the payload configurable
    response.body
  end

  def check_webdav_endpoint(uri)
    http_request :propfind, uri
  end

  def check_api_endpoint(response)
    return true if response.header['Content-Type'] =~ /application/
  false
  end

  def check_forms(response_body)
    return true if response_body =~ /<form/i
  false
  end

end
end
end
