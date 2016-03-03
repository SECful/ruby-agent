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
        Rails.logger.info 'secful: initialize'
        @secful_key = secful_key
        Rails.logger.info 'secful: secful_key'
        @agent_identifier = SecureRandom.hex
        Rails.logger.info 'secful: agent_identifier'
        @machine_ip = Socket.ip_address_list.detect(&:ipv4_private?).try(:ip_address)
        Rails.logger.info 'secful: machine_ip'
        #@@queue = SizedQueue.new(MAX_QUEUE_SIZE)
        #Rails.logger.info 'secful: queue init ' + @@queue.__id__.to_s
        @worker_mutex = Mutex.new
        @pid_to_socket = {}
        Rails.logger.info 'secful: threads_to_sockets'
        #Thread.new { activate_workers() }
        Rails.logger.info 'secful: activate_workers()'
        @headers = { 'Agent-Type' => 'Ruby',
                      'Agent-Version' => '1.0',
                      'Agent-Identifier' => @agent_identifier,
                      'Authorization' => 'Bearer ' + @secful_key }
        #@ws = WebSocket::Client::Simple.connect @socket_path, verify_mode: @verify_mode, headers: @headers
        @ws = nil
        Rails.logger.info "Process id: " + Process.pid.to_s
        Rails.logger.info 'done init'
      rescue Exception => e  
        Rails.logger.info 'secful: init-exception: ' + e.message
        Rails.logger.info 'secful: init-trace: ' + e.backtrace.inspect
      end
    end

    def call(env)
      Rails.logger.info "Process id: " + Process.pid.to_s
      Rails.logger.info "secful: call"
      if !@pid_to_socket.has_key?(Process.pid)
        Rails.logger.info "Adding pid " + Process.pid.to_s + " to pid_to_socket"
        @pid_to_socket[Process.pid] = nil
      end
      if !defined? @queue
        Rails.logger.info "init queue"
        @queue = SizedQueue.new(MAX_QUEUE_SIZE)
      end

      #connect_to_ws
      dup._call env
      #begin
      #  @worker_mutex.synchronize do
      #    puts 'secful: call'
      #    puts '1'
      #    puts '2'
      #  end
      #  handle_request(env)
      #  puts '3'
      #  @app.call(env)
      #  #dup._call(env)
      #  #_call(env)
      #rescue Exception => e
      #  puts 'secful: call-exception: ' + e.message
      #  puts 'secful: call-trace: ' + e.backtrace.inspect
      #  @app.call(env)
      #end
    end

    protected

    def _call(env)
      Rails.logger.info 'secful: _call'
      #status, headers, body = @app.call(env)
      #Rails.logger.info 'secful: queue.len = ' + @@queue.length.to_s + ' id: ' + @@queue.__id__.to_s
      Rails.logger.info 'handle request'
      @worker_mutex.synchronize do
        handle_request(env)
        #Rails.logger.info 'secful: queue.len = ' + @@queue.length.to_s + ' id: ' + @@queue.__id__.to_s
        #if @@queue.length < MAX_QUEUE_SIZE
        #  @@queue << env
        #connect_to_ws
        #  Rails.logger.info 'secful: about to put in queue'
        #  Rails.logger.info 'secful: put in queue'
        #end
      end
      #return [status, headers, body]
      @app.call(env)
    end

    def activate_workers
      puts 'secful: activate_workers'
      NUM_OF_THREADS.times do
        puts 'secful: new thread'
        thr = Thread.new {worker()}
        puts 'secful: thread started ' + thr.__id__.to_s
      end
    end

    def worker
      loop do
        begin
          #puts 'secful: worker start: ' + Thread.current.__id__.to_s + ' queue: ' + @queue.__id__.to_s
          #env = @queue.pop
          puts 'worker queue id: ' + @queue.__id__.to_s + ' len: ' + @queue.length.to_s
          sleep(5)
          #puts 'secful: worker poped'
          #if env
          #  puts 'secful: env'
          #  connect_to_ws(Thread.current)
          #  handle_request(env)
          #  puts 'scful: worker done'
          #end
        rescue Exception => e
          puts 'secful: worker-exception: ' + e.message
          puts 'secful: worker-trace: ' + e.backtrace.inspect
        end
      end
    end

    def connect_to_ws
      begin
        Rails.logger.info 'secful: connect_to_ws'
        #ws = @threads_to_sockets[thr]
        #ws = @ws
        #if @ws
        Rails.logger.info 'secful: creating ws'
        headers = { 'Agent-Type' => 'Ruby',
                    'Agent-Version' => '1.0',
                    'Agent-Identifier' => @agent_identifier,
                    'Authorization' => 'Bearer ' + @secful_key }
        ws = WebSocket::Client::Simple.connect @socket_path, verify_mode: @verify_mode, headers: headers
        sleep(3)
        Rails.logger.info 'secful: connected to ws'
        #end
        if !ws.open?
          Rails.logger.info 'secful: socket sleeping'
          sleep(5)
        end
        if !ws.open?
          Rails.logger.info 'secful: closing socket'
          ws.close()
          ws = nil
        end
      rescue nil
      end
      @pid_to_socket[Process.pid] = ws
    end

    def handle_request(env)
      request_hash = {}
      if env['rack.url_scheme'] == 'http'
        Rails.logger.info 'secful: writing env'
        write_env(request_hash, env)
        #ws = @threads_to_sockets[Thread.current]
        begin
          Rails.logger.info 'secful: sending'
          #@ws.send request_hash.to_json
          ws = @pid_to_socket[Process.pid]
          if ws
            ws.send request_hash.to_json
          else
            connect_to_ws
          end
          Rails.logger.info 'secful: sent'
        rescue Exception => e
          Rails.logger.info 'secful: handle_request-exception: ' + e.message
          connect_to_ws
          #Rails.logger.info 'secful: handle_request-trace: ' + e.backtrace.inspect
          #if @ws
          #  @ws.close()
          #@ws = nil
          #end rescue nil
          #@threads_to_sockets[Thread.current] = nil
        end
      end rescue nil
    end

    def write_env(request_hash, env)
      write_request_line request_hash, env
      write_headers request_hash, env
      write_post_body request_hash, env
    end

    def write_request_line(request_hash, env)
      puts 'method: ' + env['REQUEST_METHOD']
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
