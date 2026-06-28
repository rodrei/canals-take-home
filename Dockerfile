# Single-stage development image. Optimized for "clone -> docker compose up"
# with zero local Ruby. (A production build would be multi-stage, non-root, and
# asset/bootsnap-optimized; out of scope for this assessment.)
FROM ruby:4.0

RUN apt-get update -qq && apt-get install -y postgresql-client && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "3000"]
