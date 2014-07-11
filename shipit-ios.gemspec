# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'shipit-ios/version'

Gem::Specification.new do |spec|
  spec.name          = "shipit-ios"
  spec.version       = ShipitIos::VERSION
  spec.authors       = ["Justin Mutter"]
  spec.email         = ["justin@shopify.com"]
  spec.summary       = %q{iTunes Connect app uploader.}
  spec.description   = %q{Build and upload iOS apps directly to iTunes Connect}
  spec.homepage      = "https://github.com/j-mutter/shipit-ios"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-debugger"

  spec.add_runtime_dependency "shenzhen"
  spec.add_runtime_dependency "plist"
  spec.add_runtime_dependency "xcodeproj"
end
