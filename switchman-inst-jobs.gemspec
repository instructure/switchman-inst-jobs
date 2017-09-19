# coding: utf-8

lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'switchman_inst_jobs/version'

Gem::Specification.new do |s|
  s.name     = 'switchman-inst-jobs'
  s.version  = SwitchmanInstJobs::VERSION
  s.authors  = ['Bryan Petty']
  s.email    = ['bpetty@instructure.com']

  s.summary  = 'Switchman and Instructure Jobs compatibility gem.'
  s.homepage = 'https://github.com/instructure/switchman-inst-jobs'
  s.license  = 'MIT'

  s.files    = Dir['{db,lib}/**/*']

  s.required_ruby_version = '>= 2.3'

  s.add_dependency 'inst-jobs', '>= 0.12.1', '< 0.15'
  s.add_dependency 'railties', '>= 4.2', '< 5.1'
  s.add_dependency 'switchman', '>= 1.9.7', '< 1.12'

  s.add_development_dependency 'bundler', '~> 1.15'
  s.add_development_dependency 'pg', '~> 0'
  s.add_development_dependency 'pry', '~> 0'
  s.add_development_dependency 'rake', '~> 12.0'
  s.add_development_dependency 'rspec', '~> 3.6'
  s.add_development_dependency 'rspec-rails', '~> 3.6'
  s.add_development_dependency 'rubocop', '~> 0'
  s.add_development_dependency 'simplecov', '~> 0.14'
  s.add_development_dependency 'wwtd', '~> 1.3.0'
end
