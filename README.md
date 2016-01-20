# ruby-agent
Catch traffic on ruby middleware and send it out in different threads.

Installation
------------
    add "egem 'websocket-client-simple'"
    to your Gemfile

    add "require 'rack/socket_duplex'"
    add "use Rack::SocketDuplex, 'ws://localhost:8000'"
    to your config.ru
