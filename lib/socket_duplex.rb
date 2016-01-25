require 'json'
require 'socket'

require_relative './websocket-client-simple'

module Rack
  class SocketDuplex
    VERSION = '1.0.0'

    def initialize(app, socket_path, verify_mode=OpenSSL::SSL::VERIFY_PEER)
      @app, @socket_path, @verify_mode = app, socket_path, verify_mode
      begin
        @machine_ip = Socket.ip_address_list.detect(&:ipv4_private?).try(:ip_address)
        @queue = SizedQueue.new(10)
        @threads_to_sockets = {}
        check_thread_pool()
      rescue Exception
      end
    end

    def call(env)
      begin
        check_thread_pool()
        dup._call(env)
      rescue Exception
        @app.call(env)
      end
    end

    protected

    def _call(env)
      status, headers, body = @app.call(env)
      if @queue.length < @queue.max
        @queue << env
      end
      #handle_response(status, headers, body)
      return [status, headers, body]
    end

    def check_thread_pool
      if not @threads_to_sockets.keys.map {|thr| thr.status}.any?
        close_sockets()
        @threads_to_sockets = {}
        activate_workers()
      end
    end

    def activate_workers
      3.times do
        connect_to_ws(Thread.new { worker() })
      end
    end

    def worker
      loop do
        env = @queue.pop
        if env
          connect_to_ws(Thread.current)
          handle_request(env)
        end rescue nil
      end
    end

    def connect_to_ws(thr)
      if !@threads_to_sockets[thr] or !@threads_to_sockets[thr].open?
        @threads_to_sockets[thr] = WebSocket::Client::Simple.connect @socket_path, verify_mode: @verify_mode
      end
    end

    def close_sockets
      @threads_to_sockets.values.each do |ws|
        begin
          ws.close()
        end rescue nil
      end
    end

    def handle_request(env)
      request_hash = {}
      if env['rack.url_scheme'] == 'http'
        write_env(request_hash, env)
        @threads_to_sockets[Thread.current].send request_hash.to_json
      end rescue nil
    end

    def handle_response(status, headers, body)
    end

    def write_env(request_hash, env)
      write_request_line request_hash, env
      write_headers request_hash, env
      write_post_body request_hash, env
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
        request_hash[:http][:payload] = env['rack.input'].read
        env['rack.input'].rewind
      end
    end
  end
end
