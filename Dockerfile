FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive

# Set environment variables for locale settings
ENV SHELL=/bin/bash
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# Set the working directory inside the container
WORKDIR /app

# Change ownership of /app to the "nobody" user
# Update the package index, upgrade packages, install required dependencies,
# then clean up to reduce image size
# Uncomment the locale in locale.gen and generate it
RUN chown nobody /app && \
    apt-get update -y && \
    apt-get upgrade -y && \
    apt-get install -y bash libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && \
    rm -f /var/lib/apt/lists/*_* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

# Copy the Phoenix release into the image and set ownership to "nobody"
COPY --chown=nobody:root ./_build/prod/rel/portfolio/ ./

# Open Phoenix port (4000 by default)
EXPOSE 4000

# Run the container as an unprivileged user for better security
USER nobody

# Start the Phoenix server when the container starts
SHELL ["bash", "-c"]
CMD ["/app/bin/portfolio"]
