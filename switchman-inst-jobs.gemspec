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

  s.required_ruby_version = '>= 2.5'

  s.add_dependency 'inst-jobs', '~> 1.0', '>= 1.0.3'
  s.add_dependency 'parallel', '>= 1.19'
  s.add_dependency 'railties', '>= 5.2', '< 6.1'
  s.add_dependency 'switchman', '~> 2.0'

  s.add_development_dependency 'bundler'
  s.add_development_dependency 'byebug'
  s.add_development_dependency 'imperium'
  s.add_development_dependency 'newrelic_rpm'
  s.add_development_dependency 'pg', '~> 1.0'
  s.add_development_dependency 'pry', '~> 0'
  s.add_development_dependency 'rake', '~> 13'
  s.add_development_dependency 'rspec', '~> 3.6'
  s.add_development_dependency 'rspec-rails', '~> 3.6'
  s.add_development_dependency 'rubocop', '~> 0.79.0'
  s.add_development_dependency 'rubocop-rails', '~> 2.4.2'
  s.add_development_dependency 'simplecov', '~> 0.18'
  s.add_development_dependency 'wwtd', '~> 1.4'
end
