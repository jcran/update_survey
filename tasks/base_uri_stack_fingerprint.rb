
module UpdateSurvey
module Task
class BaseUriStackFingerprint < Intrigue::Task::BaseTask
  include Intrigue::Task::Web
  include Intrigue::Task::Product

  def self.metadata
    {
      :name => "enrich/base_uri_stack_fingerprint",
      :pretty_name => "Base Uri Stack Fingerprint",
      :authors => ["jcran"],
      :description => "Fingerprints the coponents of of a uri, giving insight into the products.",
      :references => [
        "http://www.net-square.com/httprint_paper.html",
        "https://www.troyhunt.com/shhh-dont-let-your-response-headers/",
        "https://asafaweb.com/",
        "https://www.owasp.org/index.php/Category:OWASP_Cookies_Database",
        "http://stackoverflow.com/questions/31134333/this-application-has-no-explicit-mapping-for-error",
        "https://snyk.io/blog/77-percent-of-sites-still-vulnerable/"
      ],
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
    # Grab the full response 2x
    uri = _get_entity_name

    response = http_request :get,uri
    response2 = http_request :get,uri

    ## Indicators
    # Banner Grabbing / Headers (Server, X-Powered-By, X-AspNet-Version)
    # Specific Pages (trace.axd)
    # WebServer: Request/Response deviations
    # WebServer: Wrong HTTP version requests
    # WebServer: Wrong protocol s/HTTP/JUNK/g version requests
    # General fingerprinting takes all of these into account

    unless response && response2
      _log_error "Unable to receive a response for #{uri}, bailing"
      return
    end

    _log "Got server response:"
    # Save the full headers
    headers = []
    response.each_header {|h,v| _log " - #{h}: #{v}"; headers << "#{h}: #{v}" }
    @entity.set_detail("headers", headers )

    ###
    ### Fingerprint the server
    ###
    server_stack = []  # Use various techniques to build out the "stack"
    server_stack << _check_server_header(response, response2)
    uniq_server_stack = server_stack.select{ |x| x != nil }.uniq
    @entity.set_detail("server_fingerprint", uniq_server_stack)
    _log "Setting server stack to #{uniq_server_stack}"

    ###
    ### Fingerprint the app server
    ###
    app_stack = []
    app_stack.concat _check_uri(uri)
    app_stack.concat _check_cookies(response)
    app_stack.concat _check_generator(response)
    app_stack.concat _check_x_headers(response)

    # this has now been moved into Intrigue::Task::Web
    # for details on the fingerprints, see the lib/fingerprints directory
    fingerprint = fingerprint_uri(uri)
    if fingerprint
      app_stack.concat fingerprint.map{|x| "#{x[:name]} #{x[:version]}"}
      uniq_app_stack =  app_stack.select{ |x| x != nil }.uniq
      @entity.set_detail("app_fingerprint", uniq_app_stack)
      _log "Setting app stack to #{uniq_app_stack}"
    else
      entity.set_detail("app_fingerprint", [])
    end

    ###
    ### Fingerprint the js libraries
    ###
    include_stack = []
    include_stack.concat _check_page_contents_legacy(response)
    uniq_include_stack = include_stack.select{ |x| x != nil }.uniq
    @entity.set_detail("include_fingerprint", uniq_include_stack)
    _log "Setting include stack to #{uniq_include_stack}"

    ###
    ### Product matching
    ###
    # match products based on gathered server software
    products = uniq_server_stack.map{|x| product_match_http_server_banner(x).first}
    # match products based on cookies
    products.concat product_match_http_cookies(_gather_cookies(response))
    @entity.set_detail("products", products.compact)


    _finalize_enrichment
  end

  private

  def _check_page_contents_legacy(response)

    ###
    ### Security Seals
    ###
    # http://baymard.com/blog/site-seal-trust
    # https://vagosec.org/2014/11/clubbing-seals/
    #
    http_body_checks = [
      { :regex => /sealserver.trustwave.com\/seal.js/, :finding_name => "Trustwave Security Seal"},
      { :regex => /Norton Secured, Powered by Symantec/, :finding_name => "Norton Security Seal"},
      { :regex => /PathDefender/, :finding_name => "McAfee Pathdefender Security Seal"},

      ### Marketing / Tracking
      {:regex => /urchin.js/, :finding_name => "Google Analytics"},
      {:regex => /GoogleAnalyticsObject/, :finding_name => "Google Analytics"},
      {:regex => /MonsterInsights/, :finding_name => "MonsterInsights plugin"},
      {:regex => /optimizely/, :finding_name => "Optimizely"},
      {:regex => /trackalyze/, :finding_name => "Trackalyze"},
      {:regex => /doubleclick.net|googleadservices/, :finding_name => "Google Ads"},
      {:regex => /munchkin.js/, :finding_name => "Marketo"},
      {:regex => /omniture/, :finding_name => "Omniture"},
      {:regex => /w._hsq/, :finding_name => "Hubspot"},
      {:regex => /Async HubSpot Analytics/, :finding_name => "Async HubSpot Analytics Code for WordPress"},
      {:regex => /Olark live chat software/, :finding_name => "Olark"},
      {:regex => /intercomSettings/, :finding_name => "Intercom"},
      {:regex => /vidyard/, :finding_name => "Vidyard"},

      ### External accounts
      {:regex => /http:\/\/www.twitter.com.*?/, :finding_name => "Twitter"},
      {:regex => /http:\/\/www.facebook.com.*?/, :finding_name => "Facebook"},
      {:regex => /googleadservices/, :finding_name => "Google Ads"},

      ### Libraries / Base Technologies
      {:regex => /jquery.js/, :finding_name => "JQuery"},
      {:regex => /bootstrap.css/, :finding_name => "Bootstrap"},


      ### Platforms
      {:regex => /[W|w]ordpress/, :finding_name => "Wordpress"},
      {:regex => /[D|d]rupal/, :finding_name => "Drupal"},
      {:regex => /[C|c]loudflare/, :finding_name => "Cloudflare"},


      ### Provider
      #{:regex => /Content Delivery Network via Amazon Web Services/, :finding_name => "Amazon CDN"},

      ### Wordpress Plugins
      #{ :regex => /wp-content\/plugins\/.*?\//, :finding_name => "Wordpress Plugin" },
      #{ :regex => /xmlrpc.php/, :finding_name => "Wordpress API"},
      #{ :regex => /Yoast SEO Plugin/, :finding_name => "Wordpress: Yoast SEO Plugin"},
      #{ :regex => /All in One SEO Pack/, :finding_name => "Wordpress: All in One SEO Pack"},
      #{:regex => /PowerPressPlayer/, :finding_name => "Powerpress Wordpress Plugin"}
      ]
    ###

    stack = []

    # Iterate through the target strings, which can be found in the web mixin
    http_body_checks.each do |check|
      matches = response.body.scan(check[:regex])

      # Iterate through all matches
      matches.each do |match|
        stack << check[:finding_name]
      end if matches
    end
    # End interation through the target strings
    ###
  stack
  end

  def _check_uri(uri)
    _log "_check_uri called"
    temp = []
    temp << "ASP Classic" if uri =~ /.*\.asp(\?.*)?$/i
    temp << "ASP.NET" if uri =~ /.*\.aspx(\?.*)?$/i
    temp << "CGI" if uri =~ /.*\.cgi(\?.*)?$/i
    temp << "Java (JSESSIONID)" if uri =~ /jsessionid=/i
    temp << "JSP" if uri =~ /.*\.jsp(\?.*)?$/i
    temp << "PHP" if uri =~ /.*\.php(\?.*)?$/i
    temp << "Struts" if uri =~ /.*\.do(\?.*)?$/i
    temp << "Struts" if uri =~ /.*\.go(\?.*)?$/i
    temp << "Struts" if uri =~ /.*\.action(\?.*)?$/i

  temp
  end

  def _check_generator(response)
    _log "_check_generator called"
    temp = []

    # Example: <meta name="generator" content="MediaWiki 1.29.0-wmf.9"/>
    doc = Nokogiri.HTML(response.body)
    doc.xpath("//meta[@name='generator']/@content").each do |attr|
      temp << attr.value
    end

    _log "Returning: #{temp}"

  temp
  end

  def _gather_cookies(response)
    header = response.header['set-cookie']
  end

  def _check_cookies(response)
    _log "_check_cookies called"

    temp = []

    header = response.header['set-cookie']
    if header

      temp << "Apache JServ" if header =~ /^.*JServSessionIdroot.*$/
      temp << "ASP.NET" if header =~ /^.*ASPSESSIONID.*$/
      temp << "ASP.NET" if header =~ /^.*ASP.NET_SessionId.*$/
      temp << "BEA WebLogic" if header =~ /^.*WebLogicSession*$/
      temp << "BigIP" if header =~ /^.*BIGipServer*$/
      temp << "Coldfusion" if header =~ /^.*CFID.*$/
      temp << "Coldfusion" if header =~ /^.*CFTOKEN.*$/
      temp << "Coldfusion" if header =~ /^.*CFGLOBALS.*$/
      temp << "Coldfusion" if header =~ /^.*CISESSIONID.*$/
      temp << "ExpressJS" if header =~ /^.*connect.sid.*$/
      temp << "IBM WebSphere" if header =~ /^.*sesessionid.*$/
      temp << "IBM Tivoli" if header =~ /^.*PD-S-SESSION-ID.*$/
      temp << "IBM Tivoli" if header =~ /^.*PD_STATEFUL.*$/
      temp << "Mint" if header =~ /^.*MintUnique.*$/
      temp << "Moodle" if header =~ /^.*MoodleSession.*$/
      temp << "Omniture" if header =~ /^.*sc_id.*$/
      temp << "PHP" if header =~ /^.*PHPSESSION.*$/
      temp << "PHP" if header =~ /^.*PHPSESSID.*$/
      temp << "Spring" if header =~ /^.*JSESSIONID.*$/
      temp << "Yii PHP Framework 1.1.x" if header =~ /^.*YII_CSRF_TOKEN.*$/       # https://github.com/yiisoft/yii
      temp << "MediaWiki" if header =~ /^.*wiki??_session.*$/

    end

    _log "Cookies: #{temp}"

    temp
  end




  def _check_x_headers(response)
    _log "_check_x_headers called"

    temp = []

    ### X-AspNet-Version-By Header
    header = response.header['X-AspNet-Version']
    temp << "#{header}".gsub("X-AspNet-Version:","") if header

    ### X-Powered-By Header
    header = response.header['X-Powered-By']
    temp << "#{header}".gsub("X-Powered-By:","") if header

    ### Generator
    header = response.header['x-generator']
    temp << "#{header}".gsub("x-generator:","") if header

    ### x-drupal-cache
    header = response.header['x-drupal-cache']
    temp << "Drupal" if header

    header = response.header['x-batcache']
    temp << "Wordpress Hosted" if header

    header = response.header['fastly-restarts']
    temp << "Fastly CDN" if header

    # TODO - magento
    ###[_]  - x-magento-lifetime: 86400
    ###[_]  - x-magento-action: cms_index_index

    header = response.header['x-pingback']
    if header
      if "#{header}" =~ /xmlrpc.php/
        temp << "Wordpress API"
      else
        _log_error "Got x-pingback header: #{header}, but can't do anything with it"
      end
    end

    _log "Returning: #{temp}"
  temp
  end

  def _check_server_header(response, response2)
    _log "_check_server_header called"

    ### Server Header
    server_header = _resolve_server_header(response.header['server'])

    if server_header
      # If we got the same 'server' header in both, create a WebServer entity
      # Checking for both gives us some assurance it's not totally bogus (e)
      # TODO: though this might miss something if it's a different resolution path?
      if response.header['server'] == response2.header['server']
        _log "Returning: #{server_header}"

        return server_header
      else
        _log_error "Header did not match!"
        _log_error "1: #{response.header['server']}"
        _log_error "2: #{response2.header['server']}"
      end
    else
      _log_error "No 'server' header!"
    end

  return nil
  end

  # This method resolves a header to a probable name in the case of generic
  # names. Otherwise it just matches what was sent.
  def _resolve_server_header(header_content)
    return nil unless header_content

    # Sometimes we're given a generic name, so keep track of the probable server for that name
    aliases = [
      {:given => "Server", :probably => "Apache (Server)"}
    ]

    # Set the default
    web_server_name = header_content

    # Check all aliases, returning the probable name if it matches exactly
    aliases.each do |a|
      web_server_name = a[:probably] if a[:given] =~ /#{Regexp.escape(header_content)}/
    end

    _log "Resolved: #{web_server_name}"

  web_server_name
  end

end
end
end
