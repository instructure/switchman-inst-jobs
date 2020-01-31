FROM instructure/rvm

WORKDIR /app

COPY switchman-inst-jobs.gemspec Gemfile /app/
COPY lib/switchman_inst_jobs/version.rb /app/lib/switchman_inst_jobs/version.rb

USER root
RUN mkdir -p /app/coverage \
             /app/log \
             /app/spec/gemfiles/.bundle \
             /app/spec/dummy/log \
             /app/spec/dummy/tmp \
 && chown -R docker:docker /app

USER docker
RUN /bin/bash -lc "cd /app && rvm-exec 2.4 bundle install --jobs 5"
RUN /bin/bash -lc "rvm-exec 2.7 gem install bundler -v '1.17.3'"
COPY . /app

USER root
RUN chown -R docker:docker /app
USER docker

CMD /bin/bash -lc "rvm-exec 2.4 bundle exec wwtd"
