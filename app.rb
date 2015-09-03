require 'sinatra'
require 'vcr'
require 'cgi'
require 'pry'
require 'pry-remote'
require "json"
require 'faraday'
require "logger"
require 'faraday_middleware'


class App < Sinatra::Base

  set :show_exceptions, false

  logger = Logger.new $stderr
  logger.level = Logger::DEBUG

  configure do
    VCR.configure do |c|
      c.cassette_library_dir = "spec/fixtures"
      c.allow_http_connections_when_no_cassette = true
      c.default_cassette_options = { :record => :none, :allow_playback_repeats => true }
      c.hook_into :webmock
    end
  end

  helpers do

    # From https://github.com/unixcharles/vcr-remote-controller

    def cassettes
      Dir["#{VCR::configuration.cassette_library_dir}/**/*.yml"].map do |f|
        f.match(/^#{Regexp.escape(VCR::configuration.cassette_library_dir.to_s)}\/(.+)\.yml/)[1]
      end
    end

    def current_cassette
      VCR.current_cassette ? VCR.current_cassette.name : nil
    end

    def current_cassette_new_recorded_interactions
      VCR.current_cassette.new_recorded_interactions.map(&:to_yaml).join("\n\n") if cassette?
    end

    def cassette?
      VCR.current_cassette
    end

    def current_cassette_empty?
      VCR.current_cassette.new_recorded_interactions.size == 0 if cassette?
    end

    def current_cassette_record_mode
      VCR.current_cassette.record_mode if cassette?
    end

    def default_record_mode
      VCR::configuration.default_cassette_options[:record]
    end

  end

  get '/?' do
    status 200
    body '{"status":"OK"}'
  end

  def self.mock_handler(url, &block)
    get(url, &block)
    post(url, &block)
    put(url, &block)
    patch(url, &block)
    delete(url, &block)
  end

  mock_handler '/*' do

    @platform = "https://enpoint.com"
		@http_request_method = request.request_method	# GET, POST, DELETE, PATCH
		@request_path = request.path_info		# /documents/1232323232

    request_headers =
    {
      'Accept' 				=> request.env['HTTP_ACCEPT'],
      'Accept-Encoding'		=> request.env['HTTP_ACCEPT_ENCODING'],
      'Content-Disposition' 	=> request.env['HTTP_CONTENT_DISPOSITION'],
      'If-Unmodified-Since'   => request.env['HTTP_IF_UNMODIFIED_SINCE'],
      'Link' 					=> request.env['HTTP_LINK'],
      'Authorization' 		=> request.env['HTTP_AUTHORIZATION'],
      'User-Agent' 			=> request.env['HTTP_USER_AGENT'],
      'Content-Length'		=> request.env['CONTENT_LENGTH'],
      'Content-Type'			=> request.env['CONTENT_TYPE']
    }

  request_query_hash = request.env['rack.request.query_hash']

  if request.get? || request.delete?
    request_parameters = request.env['rack.request.query_hash']
  elsif request.post? || request.patch? || request.put?
	  request_parameters = request.env['rack.request.form_hash']
		if request_parameters.nil?
			request.body.rewind
			request_parameters = request.body.read
		end
	end
	request_headers.delete_if { |k, v| v.nil? || v.empty? }

    # Update request with the platform access_token
  # if !@request_headers['Authorization'].nil?
  #   @request_headers['Authorization'] = "Bearer #{access_token}"
  # if @request_parameters['access_token'].nil?
  #    @request_parameters['access_token'] = access_token
  # end

    logger.debug "request_headers : #{@request_headers}"
    p "---"*20
    p request.env["rack.request.form_hash"]
    p request.env["rack.request.query_hash"]
    p request.env["rack.request.query_string"]
    p request.env["rack.request.form_vars"]
    p "---"*20
    logger.debug "request_parameters : #{@request_parameters}"
   VCR.use_cassette(request_hash, :record => :new_episodes) do

    response = case @http_request_method
               when "GET"
                  connection.get @request_path, request_parameters, request_headers
               when "PUT"
                  #  @response = Unirest.put(endpoint, headers: @request_headers, parameters: @request_parameters )
               when "POST"
                 connection.post do |req|
                   req.url @request_path
                   req.headers = request_headers
                   req.body = request_parameters
                 end
                  #  @response = Unirest.post(endpoint, headers:@request_headers, parameters:@request_parameters)
               when "DELETE"
                  #  @response = Unirest.delete(endpoint, headers:@request_headers, parameters:@request_parameters)
               when "PATCH"
                  #  @response = Unirest.patch(endpoint, headers:@request_headers, parameters:@request_parameters)
               else
                 raise "Unknown http request #{http_request_method}"
            	end
    logger.debug response
    status response.status
    body response.body
  end
end

  def request_hash
    sha256 = Digest::SHA256.new

    sha256 << @http_request_method
    sha256 << @request_path
    sha256.to_s
  end

  def connection
    connection ||= Faraday.new(:url => @platform ) do |c|
      c.request  :url_encoded
      c.response :logger
      c.adapter  Faraday.default_adapter
    end
  end
end
