# ===========================================
# EMAIL SENDER TRACKING SERVICE
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
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# Рабочая директория
WORKDIR /app

# Копирование Gemfile
COPY Gemfile Gemfile.lock* ./

# Установка gems
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# Копирование приложения
COPY . .

# Create necessary directories
RUN mkdir -p public log

# Порт
EXPOSE 3001

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:3001/health || exit 1

# Запуск
CMD ["bundle", "exec", "puma", "-p", "3001", "-C", "config.ru"]
