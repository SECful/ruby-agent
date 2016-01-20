require 'json'
require 'socket'
require 'websocket-client-simple'

module Rack
  class SocketDuplex
    VERSION = '1.0.0'

    def initialize(app, socket_path)
      @app, @socket_path = app, socket_path
      begin
        @machine_ip = Socket.ip_address_list.detect(&:ipv4_private?).try(:ip_address)
      rescue
      rescue Exception
      end
      Thread.new { connect_to_ws() }
    end

    def call(env)
      begin
        Thread.new { connect_to_ws() }
        dup._call(env)
      rescue
      rescue Exception
      end
    end

    def _call(env)
      status, headers, body = @app.call(env)
      Thread.new{ handle_request(env) }
      Thread.new{ handle_response(status, headers, body)}
      return [status, headers, body]
    end

    protected

    def connect_to_ws
      if !@ws or !@ws.open?
        @ws = WebSocket::Client::Simple.connect @socket_path
      end
    end

    def handle_request(env)
      request_hash = {}
      if env['rack.url_scheme'] == 'http'
        write_env(request_hash, env)
        @ws.send request_hash.to_json
      end
    end

    def handle_response(status, headers, body)
    end

    def write_env(request_hash, env)
      write_request_line request_hash, env
      write_headers      request_hash, env
      write_post_body    request_hash, env
    end

    def write_request_line(request_hash, env)
      path_with_query_string = env['PATH_INFO']
      path_with_query_string << "?#{env['QUERY_STRING']}" if env['QUERY_STRING'].length > 0
      request_hash[:http] = {path: path_with_query_string,
                             version: env['HTTP_VERSION'],
                             method: env['REQUEST_METHOD']}
      request_hash[:agentType] = 'Ruby'
      request_hash[:agentVersion] = '1.0'
      request_hash[:agentIdentifier] = '3478529645'
      request_hash[:userSrcIp] = env['REMOTE_ADDR']
      request_hash[:companyDstIp] = @machine_ip || env['SERVER_NAME']
    end

    def write_headers(request_hash, env)
      headers = env.select { |k, v| k =~ /^HTTP_|CONTENT_/ }
      headers.delete('HTTP_VERSION')

      request_hash[:http][:headers] = headers_arr = []
      headers.each do |k,v|
        headers_arr << {key: k, value: v}
      end
    end

    def write_post_body(request_hash, env)
      if env['CONTENT_LENGTH'] && (content_length = env['CONTENT_LENGTH'].to_i) > 0
        request_hash[:htp][:payload] = env['rack.input'].read
        env['rack.input'].rewind
      end
    end
  end
end
