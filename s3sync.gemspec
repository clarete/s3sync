# -*- mode: ruby; coding: utf-8; -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 's3sync/version'

Gem::Specification.new do |spec|
  spec.name          = "s3sync"
  spec.version       = S3Sync::VERSION
  spec.authors       = ["Lincoln de Sousa"]
  spec.email         = ["lincoln@comum.org"]
  spec.description   = 'Tool belt for managing your S3 buckets'
  spec.summary       = 's3sync is a library that aggregates a good range of features for managing your Amazon S3 buckets. It also provides basic interactive client'

  spec.homepage      = "https://github.com/clarete/s3sync"
  spec.license       = "MIT"
  spec.required_ruby_version = '~>2'

  spec.files         = `git ls-files lib bin`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }

  # Library requirements
  spec.add_dependency "aws-sdk", "< 2.2"
  spec.add_dependency "cmdparse", "~> 3.0"

  # Development requirements
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "bump"
end
