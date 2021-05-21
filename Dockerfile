FROM instructure/rvm

WORKDIR /app

USER root
RUN chown -R docker:docker /app
USER docker

COPY --chown=docker:docker switchman-inst-jobs.gemspec Gemfile /app/
COPY --chown=docker:docker lib/switchman_inst_jobs/version.rb /app/lib/switchman_inst_jobs/version.rb

RUN mkdir -p /app/coverage \
             /app/log \
             /app/spec/gemfiles/.bundle \
             /app/spec/dummy/log \
             /app/spec/dummy/tmp

RUN /bin/bash -lc "cd /app && rvm-exec 2.6 bundle install --jobs 5"
RUN /bin/bash -lc "rvm-exec 2.6 gem install bundler -v '2.2.17' && rvm-exec 2.7 gem install bundler -v '2.2.17'"
COPY --chown=docker:docker . /app

CMD /bin/bash -lc "rvm-exec 2.6 bundle exec wwtd"
