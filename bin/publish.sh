#!/bin/bash
# shellcheck shell=bash

set -ex

current_version=$(ruby -e "require '$(pwd)/lib/switchman_inst_jobs/version.rb'; puts SwitchmanInstJobs::VERSION;")
existing_versions=$(gem list --exact switchman-inst-jobs --remote --all | grep -o '\((.*)\)$' | tr -d '() ')

if [[ $existing_versions == *$current_version* ]]; then
  echo "Gem has already been published ... skipping ..."
else
  gem build ./switchman-inst-jobs.gemspec
  find switchman-inst-jobs-*.gem | xargs gem push
fi
