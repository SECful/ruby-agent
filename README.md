# ruby-agent
Secure Ruby on Rails with SECful.

Installation
------------
    1. Add the following to your Gemfile:
       gem 'socket_duplex', :git => 'git@github.com:SECful/ruby-agent.git'

    2. Add the following to your config.ru:
       require 'socket_duplex'
       use Rack::SocketDuplex, 'wss://localhost:7000', 'token'

       For a non SSL websocket use:
       use Rack::SocketDuplex, 'ws://localhost:7000', 'token', OpenSSL::SSL::VERIFY_NONE

