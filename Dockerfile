# Base image — shared foundation for both dev services
FROM node:20-alpine AS base
WORKDIR /app

# Frontend dev stage
# Source and node_modules are provided via bind-mount volumes at runtime.
# The package.json copy here is for image-only builds; compose overrides with volumes.
FROM base AS frontend
COPY fresh-price-front/package*.json ./
EXPOSE 5173
ENV VITE_PORT=5173
ENV CHOKIDAR_USEPOLLING=true
CMD ["npm", "run", "dev"]

# Backend dev stage
# Native addon build tools (bcrypt, argon2, etc.) are required only here.
FROM base AS backend
RUN apk add --no-cache python3 make g++
COPY fresh-price-backend/package*.json ./
EXPOSE 4000
ENV NODE_ENV=development
CMD ["npm", "run", "dev"]
