# AIP Certificate Server — Unified Deployment & Dependency Guide

## Overview

This document consolidates all major installation, configuration, and usage instructions from the repository’s documentation and source analysis. It provides a rationalized, streamlined guide for deploying and maintaining the AIP certificate server and its components.

---

## Main Components

- **cert_api.php** — The central Certificate Authority API (PHP).
- **Shell scripts** — For setup, diagnostics, certificate requests, and installation.
- **Configuration files** — Example: `config.env`, `ca-client.conf`.
- **Web GUI** — Located in `ca-web-gui` (see its README for frontend-specific details).

---

## Dependency List

### 1. Server/Container Dependencies

- **PHP** (typically >=7.0; check your distro/package manager)
- **php-openssl** extension
- **OpenSSL** (CLI tools)
- **curl** (for API requests)
- **Apache2 or Nginx** (or alternative web server supporting PHP)
- **bash** (for running shell scripts)
- **coreutils**, **util-linux** (standard Unix tools used in scripts)
- **jq** (for JSON parsing in shell scripts, if used)
- **Docker** (if using container setup via `create-ca-container.sh`)

### 2. Optional/Frontend

- **A web browser** (for accessing the GUI)
- **Node.js/npm** (if rebuilding frontend assets in `ca-web-gui`)

---

## Installation Commands

### On Ubuntu/Debian

```bash
sudo apt update
sudo apt install -y php php-openssl openssl curl apache2 jq git
```

### On CentOS/RHEL

```bash
sudo dnf install -y php php-openssl openssl curl httpd jq git
```

### For Docker (if using containers)

```bash
sudo apt install -y docker.io
# or
sudo dnf install -y docker
```

### For Node.js (if modifying ca-web-gui)

```bash
sudo apt install -y nodejs npm
# or use nvm for latest Node.js
```

---

## Setup Steps

1. **Clone the repository:**
    ```bash
    git clone https://github.com/DXCSithlordPadawan/aip-cert-server.git
    cd aip-cert-server
    ```

2. **Set up environment configuration:**
    - Edit `config.env` and `ca-client.conf` with your values.

3. **Run server setup scripts as needed:**
    ```bash
    bash setup-ca-server.sh
    bash install-ca-api.sh
    # For diagnostics:
    bash ca-diagnostics.sh
    ```

4. **Start Web Server:**
    - Place `cert_api.php` and related files in your web root or configure Apache/Nginx as needed.

5. **(Optional) Build and run Docker container:**
    ```bash
    bash create-ca-container.sh
    ```

---

## Usage

- **API Usage:** See `Certificate-Authority-API.md` for endpoints and usage samples.
- **Web GUI:** Enter `ca-web-gui` directory and follow its README if available.
- **Command-line:** Use `request-cert.sh` to request certificates and `fix-serial-numbers.sh` for serial corrections.

---

## Documentation

- See the following markdown files for details:
    - `README.md`: Basic overview.
    - `Certificate-Authority-API.md`: REST API usage.
    - `ca-server-readme.md`: Server-specific notes.
    - `fixes-installation-guide.md`: Troubleshooting and fixes.
    - `Overview-Deploying-cert-server.md`: End-to-end deployment notes.
    - `analysed-ca-function-php-code.md`, `amendments-to-code.md`: Code-level explanations.
    - `proxmox-ca-server-setup.md`: For Proxmox integration.

---

## Troubleshooting

- Use `ca-diagnostics.sh` for basic health checks.
- Check web server logs for PHP/OpenSSL errors.
- Ensure all config files (`config.env`, `ca-client.conf`) are filled and permissions allow server access.
- For frontend build issues, ensure Node.js is recent and all npm dependencies are installed.

---

## Maintenance

- Regularly update system packages and PHP modules.
- Rotate CA/private keys and review certificate policies as needed.
- Backup configuration and issued certificate databases.
