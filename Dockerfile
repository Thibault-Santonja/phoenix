# ============================================================================
# Multi-stage Dockerfile for Production
# ============================================================================
# Optimized for size, security, and reproducibility
# - Alpine Linux for minimal image size (~50-80MB vs ~250MB Ubuntu)
# - Multi-stage build for clean separation of build/runtime dependencies
# - Non-root user for security
# - Health check for container orchestration
# ============================================================================

# ============================================================================
# Stage 1: Builder
# ============================================================================
FROM hexpm/elixir:1.18.3-erlang-27.3-alpine-3.21.3 AS builder

# For Kamal deployment
LABEL service=portfolio

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    python3 \
    vips-dev \
    vips-tools \
    perl-image-exiftool

# Set build ENV
ENV MIX_ENV=prod

# Create app directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy assets files
COPY assets/package*.json assets/
RUN npm --prefix assets ci --progress=false --no-audit --loglevel=error

# Copy application code
COPY priv priv
COPY lib lib
COPY config config
COPY assets assets

# Compile assets
RUN mix assets.deploy

# Compile application
RUN mix compile

# Build release
RUN mix release

# ============================================================================
# Stage 2: Runtime
# ============================================================================
FROM alpine:3.21 AS runtime

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses-libs \
    libstdc++ \
    libgcc \
    bash \
    vips \
    vips-tools \
    perl-image-exiftool \
    ca-certificates

# Create non-root user
RUN addgroup -g 1000 portfolio && \
    adduser -D -u 1000 -G portfolio portfolio

# Set working directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=portfolio:portfolio /app/_build/prod/rel/portfolio ./

# Create directories for uploads
RUN mkdir -p /app/priv/static/uploads && \
    chown -R portfolio:portfolio /app

# Switch to non-root user
USER portfolio

# Set environment
ENV MIX_ENV=prod \
    PORT=4000 \
    SHELL=/bin/bash \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true

# Expose port
EXPOSE 4000

# Health check (lightweight, fast endpoint)
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider --timeout=2 http://localhost:4000/health || exit 1

# Start command
CMD ["/app/bin/portfolio", "start"]
