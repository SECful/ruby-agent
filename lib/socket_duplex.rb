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
        puts 'secful: initialize'
        @secful_key = secful_key
        puts 'secful: secful_key'
        @agent_identifier = SecureRandom.hex
        puts 'secful: agent_identifier'
        @machine_ip = Socket.ip_address_list.detect(&:ipv4_private?).try(:ip_address)
        puts 'secful: machine_ip'
        @queue = SizedQueue.new(MAX_QUEUE_SIZE)
        puts 'secful: queue'
        @threads_to_sockets = {}
        puts 'secful: threads_to_sockets'
        Thread.new { activate_workers() }
        puts 'secful: activate_workers()'
      rescue Exception => e  
        puts 'secful: init-exception: ' + e.message  
        puts 'secful: init-trace: ' + e.backtrace.inspect
      end
    end

    def call(env)
      begin
        puts 'secful: call'
        dup._call(env)
      rescue Exception => e
        puts 'secful: call-exception: ' + e.message  
        puts 'secful: call-trace: ' + e.backtrace.inspect
        @app.call(env)
      end
    end

    protected

    def _call(env)
      puts 'secful: _call'
      status, headers, body = @app.call(env)
      puts 'secful: app.call'
      puts 'secful: queue.len = ' + @queue.length.to_s
      if @queue.length < @queue.max
        puts 'secful: put in queue'
        @queue << env
      end
      return [status, headers, body]
    end

    def activate_workers
      puts 'secful: activate_workers'
      NUM_OF_THREADS.times do
        puts 'secful: new thread'
        Thread.new {worker()}
        puts 'secful: thread started'
      end
    end

    def worker
      loop do
        puts 'secful: worker start'
        env = @queue.pop
        puts 'secful: workers poped'
        if env
          puts 'secful: env'
          connect_to_ws(Thread.current)
          handle_request(env)
        end rescue nil
      end
    end

    def connect_to_ws(thr)
      begin
        puts 'secful: connect_to_ws'
        ws = @threads_to_sockets[thr]
        if !ws
          puts 'secful: creating ws'
          headers = { 'Agent-Type' => 'Ruby',
                      'Agent-Version' => '1.0',
                      'Agent-Identifier' => @agent_identifier,
                      'Authorization' => 'Bearer ' + @secful_key }
          ws = WebSocket::Client::Simple.connect @socket_path, verify_mode: @verify_mode, headers: headers
          sleep(3)
          puts 'secful: connected to ws'
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
      if env['rack.url_scheme'] == 'http'
        puts 'secful: writing env'
        write_env(request_hash, env)
        ws = @threads_to_sockets[Thread.current]
        begin
          puts 'secful: sending'
          ws.send request_hash.to_json
          puts 'secful: sent'
        rescue Exception => e
          puts 'secful: handle_request-exception: ' + e.message  
          puts 'secful: handle_request-trace: ' + e.backtrace.inspect
          if ws
            ws.close()
          end rescue nil
          @threads_to_sockets[Thread.current] = nil
        end
      end rescue nil
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
