# This file is used by Rack-based servers to start the application.

require ::File.expand_path('../config/environment', __FILE__)

require "rack/socket_duplex"
#use Rack::SocketDuplex, "/tmp/rack-socket_duplex-test"
#use Rack::SocketDuplex, 'ws://127.0.0.1:8000'
#use Rack::SocketDuplex, 'ws://10.1.10.164:9999/api/agent'
use Rack::SocketDuplex, 'ws://localhost:8000'

run Rails.application
