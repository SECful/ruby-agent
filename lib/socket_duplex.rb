require 'json'
require 'socket'
require 'securerandom'

require_relative 'websocket-client-simple'

module Rack
  class SocketDuplex
    MAX_QUEUE_SIZE = 50
    NUM_OF_THREADS = 5

    def initialize(app, socket_path, secful_key, verify_mode=OpenSSL::SSL::VERIFY_PEER)
      @app, @socket_path, @verify_mode = app, socket_path, verify_mode
      begin
        @secful_key = secful_key
        @agent_identifier = SecureRandom.hex
        @machine_ip = Socket.ip_address_list.detect(&:ipv4_private?).try(:ip_address)
        @threads_to_sockets = {}
        @worker_mutex = Mutex.new
      rescue nil  
      end
    end

    def call(env)
      begin
        ensure_workers_running
        dup._call(env)
      rescue nil
        @app.call(env)
      end
    end

    protected

    def ensure_workers_running
      return if defined? @queue
      @worker_mutex.synchronize do
        return if defined? @queue
        @queue = SizedQueue.new(MAX_QUEUE_SIZE)
        activate_workers()
      end
    end 

    def _call(env)
      status, headers, body = @app.call(env)
      if @queue.length < MAX_QUEUE_SIZE - 5
        @queue << env
      end
      return [status, headers, body]
    end

    def activate_workers
      NUM_OF_THREADS.times do
        thr = Thread.new {worker()}
      end
    end

    def worker
      loop do
        begin
          env = @queue.pop
          if env
            connect_to_ws(Thread.current)
            handle_request(env)
          end
        rescue nil
        end
      end
    end

    def connect_to_ws(thr)
      begin
        ws = @threads_to_sockets[thr]
        if !ws
          headers = { 'Agent-Type' => 'Ruby',
                      'Agent-Version' => '1.0',
                      'Agent-Identifier' => @agent_identifier,
                      'Authorization' => 'Bearer ' + @secful_key }
          ws = WebSocket::Client::Simple.connect @socket_path, verify_mode: @verify_mode, headers: headers
          sleep(3)
        end
        if !ws.open?
          sleep(60)
        end
        if !ws.open?
          ws.close()
          ws = nil
        end
      rescue nil
      end
      @threads_to_sockets[thr] = ws
    end

    def handle_request(env)
      request_hash = {}
      write_env(request_hash, env)
      ws = @threads_to_sockets[Thread.current]
      begin
        ws.send request_hash.to_json
      rescue Exception => e
        if ws
          ws.close()
        end rescue nil
        @threads_to_sockets[Thread.current] = nil
      end
    end

    def write_env(request_hash, env)
      write_request_line request_hash, env
      write_headers request_hash, env
      write_post_body request_hash, env
    end

    def write_request_line(request_hash, env)
      path_with_query_string = env['PATH_INFO']
      path_with_query_string << "?#{env['QUERY_STRING']}" if env['QUERY_STRING'].length > 0
      request_hash[:request] = {path: path_with_query_string,
                                version: env['HTTP_VERSION'],
                                method: env['REQUEST_METHOD']}
      request_hash[:userSrcIp] = env['REMOTE_ADDR']
      request_hash[:companyLocalIps] = [@machine_ip || env['SERVER_NAME']]
    end

    def write_headers(request_hash, env)
      headers = env.select { |k, v| k =~ /^HTTP_/ }
      headers = Hash[headers.map { |k, v| [k[5..-1].gsub('_', '-'), v] }]
      headers.delete('VERSION')
      if env['CONTENT_TYPE']
        headers[:'CONTENT-TYPE'] = env['CONTENT_TYPE']
      end
      if env['CONTENT_LENGTH']
        headers[:'CONTENT-LENGTH'] = env['CONTENT_LENGTH']
      end

      request_hash[:request][:headers] = headers_arr = []
      headers.each do |k,v|
        headers_arr << {key: k, value: v}
      end
    end

    def write_post_body(request_hash, env)
      if env['CONTENT_LENGTH'] && (content_length = env['CONTENT_LENGTH'].to_i) > 0
        request_hash[:request][:payload] = env['rack.input'].read
        env['rack.input'].rewind
      end
    end
  end
end
