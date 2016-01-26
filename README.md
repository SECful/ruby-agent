# ruby-agent
Catch traffic on ruby middleware and send it out in different threads.

Installation
------------
    build socket_duplex gem
    "gem build socket_duplex.gemspec"

    install socket_duplex gem
    "gem install socket_duplex-1.1.gem"

    add "gem 'socket_duplex'" to your Gemfile

    add "use Rack::SocketDuplex, 'ws://localhost:8000', OpenSSL::SSL::VERIFY_NONE"
    ('wss://localhost:7000', OpenSSL::SSL::VERIFY_PEER) for SSL
    to your config.ru
