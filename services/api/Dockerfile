# ===========================================
# EMAIL SENDER API
# Dockerfile
# ===========================================

FROM ruby:3.2-slim

# Установка зависимостей
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        libpq-dev \
        libyaml-dev \
        libffi-dev \
        nodejs \
        curl \
        git \
        ca-certificates \
        gnupg \
        lsb-release \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update -qq \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# Рабочая директория
WORKDIR /app

# Копирование Gemfile
COPY Gemfile Gemfile.lock ./

# Установка gems
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Копирование приложения
COPY . .

# Precompile assets (если есть)
# RUN bundle exec rails assets:precompile

# Create necessary directories
RUN mkdir -p tmp/pids log

# Copy and set permissions for entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Порт
EXPOSE 3000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:3000/api/v1/health || exit 1

# Entrypoint
ENTRYPOINT ["docker-entrypoint.sh"]

# Запуск
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

