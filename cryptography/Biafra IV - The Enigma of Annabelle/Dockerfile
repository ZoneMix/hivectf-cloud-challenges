FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
  PYTHONUNBUFFERED=1 \
  PIP_NO_CACHE_DIR=1 \
  HOST="0.0.0.0" \
  PORT="1337" \
  FLAG="HiveCTF{CHANGE_ME_SET_YOUR_OWN_FLAG}"

WORKDIR /challenge

# System packages needed by the app
RUN apt-get update && apt-get install -y --no-install-recommends \
  supervisor \
  ncat \
  && rm -rf /var/lib/apt/lists/*

# Copy configuration files
COPY config/supervisord.conf /etc/supervisord.conf

# Install Python dependencies first for better layer caching
RUN python --version \
  && pip --version \
  && pip install --no-cache-dir py-enigma

# Copy challenge files
COPY challenge/ /challenge/

# Expose the application port
EXPOSE 9999

# Use supervisord to run the application
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]