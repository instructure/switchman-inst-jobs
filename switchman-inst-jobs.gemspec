# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "switchman_inst_jobs/version"

Gem::Specification.new do |s|
  s.name     = "switchman-inst-jobs"
  s.version  = SwitchmanInstJobs::VERSION
  s.authors  = ["Bryan Petty"]
  s.email    = ["bpetty@instructure.com"]

  s.summary  = "Switchman and Instructure Jobs compatibility gem."
  s.homepage = "https://github.com/instructure/switchman-inst-jobs"
  s.license  = "MIT"

  s.files    = Dir["{db,lib}/**/*"]

  s.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "rubygems_mfa_required" => "true"
  }

  s.required_ruby_version = ">= 3.1"

  s.add_dependency "inst-jobs", ">= 2.4.9", "< 4.0"
  s.add_dependency "parallel", ">= 1.19"
  s.add_dependency "railties", ">= 7.0", "< 7.2"
  s.add_dependency "switchman", ">= 3.5.14", "< 5.0"
end
