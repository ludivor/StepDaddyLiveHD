ARG PORT=3000
ARG PROXY_CONTENT=TRUE
ARG SOCKS5

# Only set for local/direct access. When TLS is used, the API_URL is assumed to be the same as the frontend.
ARG API_URL

# It uses a reverse proxy to serve the frontend statically and proxy to backend
# from a single exposed port, expecting TLS termination to be handled at the
# edge by the given platform.
FROM python:3.13 AS builder

RUN mkdir -p /app/.web
RUN python -m venv /app/.venv
ENV PATH="/app/.venv/bin:$PATH"

WORKDIR /app
RUN apt-get update -qq && apt-get install -y curl gcc g++
# Install python app requirements and reflex in the container
COPY requirements.txt .
RUN pip install -r requirements.txt

# Fix para Reflex init en Docker/Render
RUN pip install --upgrade pip setuptools wheel
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g npm@latest
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
# Fix deps Reflex/Pydantic para Render/Python 3.13
# Fix deps compatibles Reflex/Pydantic Python 3.13
RUN pip install --no-cache-dir --upgrade pip setuptools wheel
RUN pip install --no-cache-dir "pydantic<3,>=2.0" "pydantic-core<3" sqlmodel==0.0.20
RUN pip install --no-cache-dir "reflex<0.6"  # estable sin sqlmodel bug
RUN pip install --no-cache-dir "reflex>=0.5.9,<0.6"
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1
RUN npm install -g npm@latest bun@latest  # si usa bun

# Install reflex helper utilities like bun/node
COPY rxconfig.py ./
RUN reflex init

# Copy local context to `/app` inside container (see .dockerignore)
COPY . .

ARG PORT API_URL PROXY_CONTENT SOCKS5
# Download other npm dependencies and compile frontend
RUN REFLEX_API_URL=${API_URL:-http://localhost:$PORT} reflex export --loglevel debug --frontend-only --no-zip && mv .web/build/client/* /srv/ && rm -rf .web


# Final image with only necessary files
FROM python:3.13-slim

# Install Caddy and redis server inside image
RUN apt-get update -y && apt-get install -y caddy redis-server && rm -rf /var/lib/apt/lists/*

ARG PORT API_URL
ENV PATH="/app/.venv/bin:$PATH" PORT=$PORT REFLEX_API_URL=${API_URL:-http://localhost:$PORT} REDIS_URL=redis://localhost PYTHONUNBUFFERED=1 PROXY_CONTENT=${PROXY_CONTENT:-TRUE} SOCKS5=${SOCKS5:-""}

WORKDIR /app
COPY --from=builder /app /app
COPY --from=builder /srv /srv

# Needed until Reflex properly passes SIGTERM on backend.
STOPSIGNAL SIGKILL

EXPOSE $PORT

# Starting the backend.
CMD caddy start && \
    redis-server --daemonize yes && \
    exec reflex run --env prod --backend-only
