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
   task backend:cmd -- npm run test:unit
   task frontend:cmd -- npm run test:unit
   task migrate
   ```

   Generic service command format:
   ```sh
   task cmd SERVICE=backend -- npm run test:unit
   ```

   For production swarm deploy:
   ```sh
   docker stack deploy -c docker-compose.prod.yml freshprice
   ```
