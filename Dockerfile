# Stage 1: Build native Node.js modules
FROM node:22-slim AS builder

WORKDIR /app

# Install build tools needed for native modules (better-sqlite3, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy package files and install production dependencies
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Stage 2: Build Python virtual environment
FROM python:3.10-slim AS python-builder

WORKDIR /app

# Install build tools for Python native extensions
RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /app/
RUN python3 -m venv /app/venv
ENV PATH="/app/venv/bin:$PATH"
# For CPU-only PyTorch (saves ~1.5GB), uncomment the next line and remove torch from requirements.txt:
# RUN pip install --no-cache-dir torch==2.5.1 --index-url https://download.pytorch.org/whl/cpu
RUN pip install --upgrade pip && pip install --no-cache-dir -r requirements.txt

# Stage 3: Production image
FROM node:22-slim

WORKDIR /app

# Install only runtime system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 \
    python3-venv \
    curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install PM2 process manager globally
RUN npm install pm2 -g && npm cache clean --force

# Copy Python venv from builder
COPY --from=python-builder /app/venv /app/venv
ENV PATH="/app/venv/bin:$PATH"

# Copy node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy application source code
COPY . .

# Remove dev/docs files not needed in production
RUN rm -rf tests/ .git/ .github/ docs/ *.md *.png *.webp *.zip \
    eslint.config.mjs prettierrc.json jsdoc_standards.md \
    package-lock.json.bak Dockerfile.rag

# Make startup script executable
RUN chmod +x start-services.sh

# Configure persistent data volume
VOLUME ["/app/data"]

# Configure application port
EXPOSE ${PAPERLESS_AI_PORT:-3000}

# Add health check with dynamic port
HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:${PAPERLESS_AI_PORT:-3000}/health || exit 1

# Set production environment
ENV NODE_ENV=production

# Start both Node.js and Python services using our script
CMD ["./start-services.sh"]
