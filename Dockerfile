ARG  RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}

WORKDIR /app

RUN /bin/bash -lc "gem install bundler -v 2.5.23"

RUN echo "gem: --no-document" >> ~/.gemrc

COPY . /app
RUN /bin/bash -lc "bundle install --jobs 5"
