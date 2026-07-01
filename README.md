# pcdocker
PriceCheck's dockerized set-up for development

## Setup Steps

1. **Download Docker**  
	[Download Docker Desktop](https://www.docker.com/products/docker-desktop/)

2. **Check GitHub Access**  
	- platform-backend
	- [fresh-price-front](https://github.com/kraim21/fresh-price-front)  
	- [fpdocker](https://github.com/kraim21/fpdocker)

3. **Check if you have Git**  
	Open terminal and type:
	```sh
	git --version
	```
	If there is no git available:
	- Download Git using Homebrew  
	- Download Homebrew, then install Git

	**Homebrew download:**
	```sh
	/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
	```

	**Git download:**
	```sh`
	brew install git
	```

4. **Clone project files**  
	Create a new folder `freshprice` in your chosen directory.  
	Run the following:
	```sh
	git clone https://github.com/kraim21/fpdocker.git
	git clone https://github.com/kraim21/fresh-price-front.git
	git clone <backend-repository-url> platform-backend
	```

5. **Set environment variables**  
	Inside `fpdocker`, create a new file `.env` and copy the following:
	```env
	# Frontend API path and Vite dev proxy target
	API_BASE_URL=/api
	VITE_API_BASE_URL=/api
	API_PROXY_TARGET=http://backend:4000
	
	# Ports for the backend and frontend services
	BACKEND_PORT=4000
	FRONTEND_PORT=5173
	SUGILANON_PORT=3000
	
	# POSTGRES
	POSTGRES_USER=admin
	POSTGRES_PASSWORD=admin
	POSTGRES_DB=freshprice
	POSTGRES_HOST=postgres
	POSTGRES_PORT=5432
	
	# Full database URL
	DATABASE_URL=postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:5432/${POSTGRES_DB}
	
	# NGINX
	NGINX_PORT=8083
	NGINX_SSL_PORT=8443

	JWT_SECRET=change_me_to_a_strong_secret
	ALLOWED_ORIGINS=http://localhost:5173

	# Sugilanon / PhilWatch blog app
	SUGILANON_API_BASE_URL=http://localhost:4000/api
	SUGILANON_SITE_URL=http://localhost:3000

	# n8n workflow automation
	N8N_PORT=5678
	N8N_HOST=localhost
	N8N_LISTEN_ADDRESS=0.0.0.0
	N8N_PROTOCOL=http
	N8N_WEBHOOK_URL=http://localhost:5678/
	N8N_ENCRYPTION_KEY=change_me_use_a_32_char_secret_key
	N8N_SECURE_COOKIE=false
	N8N_TIMEZONE=Asia/Manila
	```

    Do the same with `fresh-price-front` and `platform-backend`. Please refer to the repository README.md

	If your local backend folder still uses the old `fresh-price-backend` name, either rename it to `platform-backend` or set `BACKEND_DIR_NAME=fresh-price-backend` in `fpdocker/.env`. Do not edit the tracked Compose file for a machine-specific folder name.

6. **Build and run the project**
   From the `fpdocker` folder, use Task for local development:
   ```sh
   task dev
   ```

   To rebuild and recreate the development services after dependency,
   Dockerfile, or Compose changes:
   ```sh
   task dev:restart
   ```

   Useful development commands:
   ```sh
   task dev:logs
   task ps
   task backend
   task frontend
   task sugilanon
   task n8n
   task backend:cmd -- npm run test:unit
   task frontend:cmd -- npm run test:unit
   task migrate
   ```

   Generic service command format:
   ```sh
   task cmd SERVICE=backend -- npm run test:unit
   ```

   Sugilanon is available locally at:
   ```text
   http://localhost:3000
   ```

   n8n is available locally at:
   ```text
   http://localhost:5678
   ```

   It runs on the same Docker network as the backend, so n8n workflows can call
   FreshPrice backend endpoints with:
   ```text
   http://backend:4000/api/...
   ```

   Keep `N8N_ENCRYPTION_KEY` stable after creating n8n credentials. Changing it
   can make saved credentials unreadable.

   For production, set the VPS values in `fpdocker/.env`:
   ```env
   SUGILANON_IMAGE_TAG=latest
   SUGILANON_API_BASE_URL=https://sugilanon.philwatch.com/api
   SUGILANON_SITE_URL=https://sugilanon.philwatch.com
   ```

   The production nginx config routes `sugilanon.philwatch.com` to the
   `sugilanon` service and proxies `sugilanon.philwatch.com/api/...` to the
   backend. Before enabling the SSL config, create a certificate for
   `sugilanon.philwatch.com` under `/etc/letsencrypt/live/sugilanon.philwatch.com`.

   For production swarm deploy:
   ```sh
   docker stack deploy -c docker-compose.prod.yml freshprice
   ```
