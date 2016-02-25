lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "socket_duplex"
  spec.version       = '1.1.6'
  spec.authors       = ["Secful"]
  spec.description   = %q{Rack middleware that duplexes HTTP traffic}
  spec.summary       = spec.description

  spec.files         = `git ls-files`.split($/).reject{|f| f == "Gemfile.lock" }
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "websocket-eventmachine-server"
  spec.add_development_dependency "eventmachine"

  spec.add_runtime_dependency "websocket"
  spec.add_runtime_dependency "event_emitter"
end
