# Switchman + Instructure Jobs Compatibility Gem

If you are using the [Switchman](https://github.com/instructure/switchman) and
[Instructure Jobs](https://github.com/instructure/inst-jobs) gems in your
application, simply include this gem to make background jobs aware of sharding.


## Requirements

* Ruby 2.3+
* Rails 4.2+


## Installation

First ensure that you have installed both Switchman and Instucture Jobs gems,
including their database migrations.

Add this line to your application's Gemfile:

```ruby
gem 'switchman-inst-jobs'
```

And then execute:

```bash
bundle
```

Or install it yourself like so:

```bash
gem install switchman-inst-jobs
```

You will also want to install the database migration necessary to include the
associated shard for any queued jobs:

```bash
bundle exec rake switchman_inst_jobs:install:migrations
bundle exec rake db:migrate
```

You can continue to use inst-jobs settings like you would normally. There is one
inst-jobs setting you may want to configure in your application though:

```ruby
Delayed::Settings.worker_procname_prefix = lambda do
  "#{Switchman::Shard.current(:delayed_jobs).id}~"
end
```


## Development

A simple docker environment has been provided for spinning up and testing this
gem with multiple versions of Ruby. This requires docker and docker-compose to
be installed. To get started, run the following:

```bash
docker-compose build --pull
docker-compose up -d postgres
docker-compose run --rm app
```

This will install the gem in a docker image with all versions of Ruby installed,
and install all gem dependencies in the Ruby 2.4 set of gems. It will also
download and spin up a PostgreSQL container for use with specs. Finally, it will
run [wwtd](https://github.com/grosser/wwtd), which runs all specs across all
supported version of Ruby and Rails, bundling gems for each combination along
the way.

The first build will take a long time, however, docker images and gems are
cached, making additional runs significantly faster.

Individual spec runs can be started like so:

```bash
docker-compose run --rm app /bin/bash -l -c \
  "BUNDLE_GEMFILE=spec/gemfiles/rails-5.0.gemfile rvm-exec 2.4 bundle exec rspec"
```

If you'd like to mount your git checkout within the docker container running
tests so changes are easier to test, use the override provided:

```bash
cp docker-compose.override.example.yml docker-compose.override.yml
```


## Making a new Release

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then just
run `bundle exec rake release`, which will create a git tag for the version,
push git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).


## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/instructure/switchman-inst-jobs.


## License

The gem is available as open source under the terms of the
[MIT License](http://opensource.org/licenses/MIT).
