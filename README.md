# Custom Frappe + ERPNext + HRMS + POS Awesome Docker Setup

This directory contains everything you need to build a single custom Docker image containing your custom GitHub versions of **Frappe**, **ERPNext**, **HRMS**, and **POS Awesome**, push it to **Docker Hub**, and run it effortlessly on any device with **Docker Compose**.

---

## 🏗️ Architecture

- **Custom Image (`DOCKER_IMAGE`)**: Contains Python virtual environment, Node/Yarn compiled assets, and your custom GitHub repositories:
  - `frappe`: [https://github.com/idibek-alimov/frappe](https://github.com/idibek-alimov/frappe) (`main`)
  - `erpnext`: [https://github.com/idibek-alimov/erpnext](https://github.com/idibek-alimov/erpnext) (`main`)
  - `hrms`: [https://github.com/idibek-alimov/hrms](https://github.com/idibek-alimov/hrms) (`main`)
  - `posawesome`: [https://github.com/idibek-alimov/posawesome](https://github.com/idibek-alimov/posawesome) (`main`)
  - `web_sync`: [https://github.com/idibek-alimov/erp_web_sync](https://github.com/idibek-alimov/erp_web_sync) (`main`)
- **Supporting Services (Official Images)**:
  - `mariadb:10.11`: Official MariaDB database configured for Frappe.
  - `redis:7-alpine`: Cache and background task queues.
  - `nginx:alpine`: Static asset serving and reverse proxy for backend & websockets.

---

## 🚀 Part 1: Build and Push (On Your Primary Machine)

### 1. Configure `.env`
Edit `docker/.env` and replace `idibek` with your actual **Docker Hub username**:

```env
DOCKER_IMAGE=your_dockerhub_username/frappe-custom:v15
DB_ROOT_PASSWORD=mariadb_root_password
ADMIN_PASSWORD=admin_password
SITE_NAME=mysite.localhost
HTTP_PORT=80
```

### 2. Build the Docker Image
Run the build script:
```bash
./scripts/build.sh
```
*(This clones your GitHub repositories, installs all Python requirements, and compiles all frontend JavaScript/CSS assets).*

### 3. Push to Docker Hub
Authenticate and push your image:
```bash
./scripts/push.sh
```
*(You can also run `docker login` and `docker push your_dockerhub_username/frappe-custom:v15` manually).*

---

## 💻 Part 2: Deploy on ANY Other Device

On any other device (server, laptop, cloud VM, etc.) where Docker is installed:

### 1. Copy the Deployment Files
You only need the `docker` directory on the target machine:
- `compose.yaml` (or `docker-compose.yml`)
- `nginx.conf`
- `.env`
- `scripts/`

### 2. Start the Services
Run:
```bash
docker compose pull
docker compose up -d
```
Docker will automatically download your custom image from Docker Hub and standard MariaDB / Redis / Nginx images, then start all services.

### 3. Create / Initialize Your Site
Run the automated site initialization script:

- **Linux / macOS / Git Bash**:
  ```bash
  ./scripts/setup-site.sh
  ```
- **Windows (PowerShell)**:
  ```powershell
  .\scripts\setup-site.ps1
  ```
*(If PowerShell blocks running scripts, run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` first).*

This automatically runs `bench new-site`, sets the Administrator password, installs `erpnext`, `hrms`, and `posawesome`, and configures the background scheduler.

### 4. Access the Site
Open your web browser and navigate to:
```
http://localhost
```
- **Username**: `Administrator`
- **Password**: (The value set in your `.env` `ADMIN_PASSWORD`, default: `admin_password`)

---

## 🛠️ Useful Management Commands

| Task | Linux / Mac / Git Bash | Windows PowerShell |
| :--- | :--- | :--- |
| **Initialize Site** | `./scripts/setup-site.sh` | `.\scripts\setup-site.ps1` |
| **Backup Site** | `./scripts/backup.sh` | `.\scripts\backup.ps1` |
| **Build Image** | `./scripts/build.sh` | `.\scripts\build.ps1` |
| **Push Image** | `./scripts/push.sh` | `.\scripts\push.ps1` |
| **View logs** | `docker compose logs -f backend` | `docker compose logs -f backend` |
| **Check service status** | `docker compose ps` | `docker compose ps` |
| **Restart services** | `docker compose restart` | `docker compose restart` |
| **Stop all services** | `docker compose down` | `docker compose down` |
| **Open Frappe Console** | `docker compose exec backend bench --site mysite.localhost console` | `docker compose exec backend bench --site mysite.localhost console` |
| **Run Migrations** | `docker compose exec backend bench --site mysite.localhost migrate` | `docker compose exec backend bench --site mysite.localhost migrate` |

---

## 🔄 Updating Your Code in the Future

When you push code updates or bugfixes to your GitHub repositories:
1. On your build machine, rebuild and push the updated image:
   ```bash
   ./scripts/build.sh
   ./scripts/push.sh
   ```
2. On any target device running the stack, pull the latest image and restart:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose exec backend bench --site mysite.localhost migrate
   ```
