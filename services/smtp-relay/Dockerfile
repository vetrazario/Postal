FROM node:18-alpine

# Install build dependencies and netcat for healthcheck
RUN apk add --no-cache python3 make g++ netcat-openbsd

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application files
COPY . .

# Create logs directory
RUN mkdir -p /app/logs && chmod 777 /app/logs

# Expose SMTP port
EXPOSE 587

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD nc -z localhost 587 || exit 1

# Run as non-root user
RUN addgroup -g 1001 -S smtprelay && \
    adduser -S smtprelay -u 1001 && \
    chown -R smtprelay:smtprelay /app

USER smtprelay

# Start server
CMD ["node", "server.js"]
