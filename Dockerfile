FROM instructure/rvm

WORKDIR /app

COPY switchman-inst-jobs.gemspec Gemfile /app/
COPY lib/switchman_inst_jobs/version.rb /app/lib/switchman_inst_jobs/version.rb

USER root
RUN chown -R docker:docker /app

USER docker
RUN /bin/bash -l -c "cd /app && rvm-exec 2.4 bundle install --jobs 5"
COPY . /app

USER root
RUN chown -R docker:docker /app
USER docker

CMD /bin/bash -l -c "rvm-exec 2.4 bundle exec wwtd"
