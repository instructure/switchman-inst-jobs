lib = File.expand_path('lib', __dir__)
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

  s.required_ruby_version = '>= 2.6'

  s.add_dependency 'inst-jobs', '~> 2.0', '>= 2.3.1'
  s.add_dependency 'parallel', '>= 1.19'
  s.add_dependency 'railties', '>= 6.1', '< 6.2'
  s.add_dependency 'switchman', '~> 3.0', '>= 3.0.1'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'diplomat', '~> 2.5.1'
  s.add_development_dependency 'newrelic_rpm'
  s.add_development_dependency 'pg', '~> 1.0'
  s.add_development_dependency 'pry', '~> 0'
  s.add_development_dependency 'rake', '~> 13'
  s.add_development_dependency 'rspec', '~> 3.10'
  s.add_development_dependency 'rspec-rails', '~> 5.0'
  s.add_development_dependency 'rubocop', '~> 1.15'
  s.add_development_dependency 'rubocop-rails', '~> 2.10'
  s.add_development_dependency 'rubocop-rake', '~> 0.5'
  s.add_development_dependency 'rubocop-rspec', '~> 2.3'
  s.add_development_dependency 'simplecov', '~> 0.21'
  s.add_development_dependency 'wwtd', '~> 1.4'
end
