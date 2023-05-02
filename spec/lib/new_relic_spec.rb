# frozen_string_literal: true

describe SwitchmanInstJobs::NewRelic, order: :defined do
  it "should not change anything if new relic is not availible" do
    described_class.enable

    expect(Delayed::Worker.new).to_not respond_to(:install_newrelic_job_tracer)
  end

  it "should prepend a new relic installer if new relic is availible" do
    require "newrelic_rpm"
    described_class.enable

    # Ideally we would test this actually subs the method, but there isn't a great
    # way to do that, and we don't want to actually initailize new relic in specs
    expect(Delayed::Worker.new).to respond_to(:install_newrelic_job_tracer)
  end
end
