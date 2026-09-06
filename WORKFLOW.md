# Deployment & Development Workflow Cheatsheet

---

## 1. On Your Main Development Computer (Build Machine)

When you finish making and testing code changes in `apps/`:

```bash
# 1. Commit and push your code to your custom GitHub repos
# (frappe, erpnext, hrms, posawesome)

# 2. Build the new Docker image and push to Docker Hub
cd docker
./scripts/build.sh
./scripts/push.sh
```

---

## 2. On Any Other Machine / Production Server (Deploy Machine)

Never compile code on deployment machines. Only pull the pre-built image from Docker Hub:

```bash
# 1. Get the docker folder
git clone https://github.com/idibek-alimov/erpnext_docker.git docker
cd docker

# 2. Pull pre-built images and start services
docker compose pull
docker compose up -d

# 3. Initialize the site (ONLY run this on fresh first-time install)
# On Linux / Mac / Git Bash:
./scripts/setup-site.sh
# On Windows (PowerShell):
.\scripts\setup-site.ps1
```

---

## 3. How to Update in the Future (On the Server)

Whenever you push a new image to Docker Hub, update your running server in seconds:

```bash
cd docker

# 1. Pull the new image and restart services
docker compose pull
docker compose up -d

# 2. Run database migrations
docker compose exec backend bench --site mysite.localhost migrate
```

> **Why this workflow?**
> Compiling Frappe + ERPNext + HRMS + POS Awesome from scratch on a server takes 15–25 minutes and can crash small servers with out-of-memory errors. Pulling the finished image takes ~1 minute with zero risk.
