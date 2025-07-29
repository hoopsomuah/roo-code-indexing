# Roo Code Indexing Docker Setup

A production-ready Docker setup for local code indexing using Qdrant vector database and Ollama for embeddings. This configuration provides a self-contained environment for the Roo code indexing system. See [roo](https://docs.roocode.com/features/codebase-indexing?utm_source=extension&utm_medium=ide&utm_campaign=settings)

## 🚀 Quick Start

1. **Clone or download this repository**
2. **Configure your environment** (optional):
   ```bash
   cp .env.example .env
   # Edit .env to customize settings
   ```
3. **Run the setup script**:
   ```bash
   # On Linux/macOS:
   chmod +x setup.sh
   ./setup.sh
   
   # On Windows (PowerShell):
   .\setup.ps1
   
   # On Windows (using Git Bash or WSL):
   bash setup.sh
   
   # Or manually with Docker:
   docker compose up -d
   
   # Or manually with Podman:
   podman compose up -d
   ```

> **Note**: The setup scripts automatically detect whether you have Docker or Podman installed and use the appropriate container runtime. Podman support requires Podman 4.0+ with compose functionality.

## 📋 System Requirements

### Memory Requirements
- **Minimum**: 16GB RAM (for `nomic-embed-text` model)
- **Recommended**: 24GB RAM (for `mxbai-embed-large` model)
- **Storage**: 10GB+ free space for models and data

### Software Requirements
- Docker 20.10+ OR Podman 4.0+
- Docker Compose 2.0+ OR Podman Compose
- curl (for health checks)

> **Note**: Podman support requires Podman 4.0+ with compose functionality. On some systems, you may need to configure Podman's socket or enable lingering for proper operation.

## 🎯 Embedding Model Selection

Choose between two embedding models based on your system capabilities:

### nomic-embed-text (Default)
- **Dimensions**: 768
- **Memory**: 16GB minimum
- **Performance**: Good balance of speed and quality
- **Best for**: Most users, smaller systems

### mxbai-embed-large
- **Dimensions**: 1024
- **Memory**: 24GB minimum
- **Performance**: Higher quality embeddings
- **Best for**: High-end systems, maximum quality

To change the model, edit the `EMBEDDING_MODEL` variable in your `.env` file:
```bash
# For nomic-embed-text (default)
EMBEDDING_MODEL=nomic-embed-text

# For mxbai-embed-large
EMBEDDING_MODEL=mxbai-embed-large
```

## 🔧 Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
# Core configuration
EMBEDDING_MODEL=nomic-embed-text
QDRANT_PORT=6333
OLLAMA_PORT=11434

# Memory limits (adjust based on your system)
OLLAMA_MEMORY_LIMIT=24G
OLLAMA_MEMORY_RESERVATION=16G
QDRANT_MEMORY_LIMIT=4G

# Storage paths
QDRANT_STORAGE_PATH=./data/qdrant
OLLAMA_MODELS_PATH=./data/ollama
```

### Port Mapping

| Service | Port | Purpose |
|---------|------|---------|
| Qdrant HTTP | 6333 | Vector database API |
| Qdrant gRPC | 6334 | High-performance gRPC API |
| Ollama | 11434 | Embedding model API |

## 📁 Data Persistence

### Local Storage Configuration

Data is persisted in local directories:

```
./data/
├── qdrant/     # Vector database storage
└── ollama/     # Downloaded models storage
```

These directories are automatically created and mounted as Docker volumes for data persistence across container restarts.

### Volume Management

- **Qdrant data**: Stored in `./data/qdrant`
- **Ollama models**: Stored in `./data/ollama`
- **Backup**: Simply copy the `./data` directory
- **Reset**: Delete `./data` directory and restart services

## 🔄 Service Management

### Starting Services

```bash
# Start all services (auto-detects Docker/Podman)
./setup.sh

# Or manually with Docker:
docker compose up -d

# Or manually with Podman:
podman compose up -d

# Start with logs
docker compose up
# or
podman compose up

# Using the setup script
./setup.sh
```

### Stopping Services

```bash
# Stop services (keeps data) - Docker
docker compose down

# Stop services (keeps data) - Podman  
podman compose down

# Stop and remove volumes (deletes data) - Docker
docker compose down -v

# Stop and remove volumes (deletes data) - Podman
podman compose down -v
```

### Restarting Services

```bash
# Restart all services - Docker
docker compose restart

# Restart all services - Podman
podman compose restart

# Restart specific service - Docker
docker compose restart qdrant
docker compose restart ollama

# Restart specific service - Podman
podman compose restart qdrant
podman compose restart ollama
```

### Auto-start with System Boot

The services are configured with `restart: unless-stopped` in the [`docker-compose.yml`](docker-compose.yml:16), which means they will automatically restart if they crash or if the container runtime (Docker/Podman) restarts. To enable full auto-start on system boot across any operating system:

#### Simple Cross-Platform Setup

1. **Configure container runtime to start at login/boot**:
   - **Windows**: Docker Desktop → Settings → General → "Start Docker Desktop when you log in" OR Podman Desktop → Settings → General → "Start Podman Desktop when you log in"
   - **macOS**: Docker Desktop → Settings → General → "Start Docker Desktop when you log in" OR Podman Desktop → Settings → General → "Start Podman Desktop when you log in"  
   - **Linux**: Enable Docker service: `sudo systemctl enable docker` OR Enable Podman service: `sudo systemctl enable podman`

2. **Start the services once**:
   ```bash
   # Using Docker
   docker compose up -d
   
   # Using Podman
   podman compose up -d
   
   # Using setup script (auto-detects)
   ./setup.sh
   ```

3. **That's it!** The services will now:
   - Start automatically when the container runtime starts (at system boot/login)
   - Restart automatically if they crash or stop unexpectedly
   - Continue running until you explicitly stop them with `[docker|podman] compose down`

#### How It Works

The [`docker-compose.yml`](docker-compose.yml:16) includes `restart: unless-stopped` for both services, which means:
- Services restart automatically if they exit unexpectedly
- Services start automatically when the container runtime (Docker/Podman) daemon starts
- Services only stop when explicitly stopped with `[docker|podman] compose down`
- Services survive system reboots as long as the container runtime starts automatically

#### Advanced Platform-Specific Options

If you need more control, you can also use platform-specific service management:

<details>
<summary>Linux (systemd) - Click to expand</summary>

Create a systemd service for more granular control:

```bash
# Create service file
sudo tee /etc/systemd/system/roo-indexing.service > /dev/null <<EOF
[Unit]
Description=Roo Code Indexing Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$(pwd)
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl enable roo-indexing.service
sudo systemctl start roo-indexing.service
```
</details>

<details>
<summary>Windows (Task Scheduler) - Click to expand</summary>

For more control than Docker Desktop's auto-start:

1. Open Task Scheduler
2. Create Basic Task → "Start Roo Indexing"
3. Trigger: "When the computer starts"
4. Action: "Start a program"
5. Program: `docker`
6. Arguments: `compose up -d`
7. Start in: `C:\path\to\your\roo-docker-setup`
</details>

<details>
<summary>macOS (launchd) - Click to expand</summary>

Create a launch daemon for system-level startup:

```bash
# Create plist file
sudo tee /Library/LaunchDaemons/com.roo.indexing.plist > /dev/null <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.roo.indexing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/docker</string>
        <string>compose</string>
        <string>up</string>
        <string>-d</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$(pwd)</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF

# Load the service
sudo launchctl load /Library/LaunchDaemons/com.roo.indexing.plist
```
</details>

## ✅ Verification

### Health Checks

The setup includes automatic health checks. Verify services are running:

```bash
# Check service status
docker compose ps
# or
podman compose ps

# Check health status
docker compose logs qdrant
docker compose logs ollama
# or
podman compose logs qdrant
podman compose logs ollama

# Manual health checks
curl http://localhost:6333/health
curl http://localhost:11434/api/tags
```

### Testing the Setup

1. **Verify Qdrant is accessible**:
   ```bash
   curl -X GET http://localhost:6333/collections
   ```

2. **Verify Ollama has the embedding model**:
   ```bash
   curl http://localhost:11434/api/tags
   ```

3. **Test embedding generation**:
   ```bash
   curl -X POST http://localhost:11434/api/embeddings \
     -H "Content-Type: application/json" \
     -d '{
       "model": "nomic-embed-text",
       "prompt": "Hello world"
     }'
   ```

### Using the Setup Scripts

#### Linux/macOS (Bash)
The bash setup script provides additional verification options:

```bash
# Verify current setup
./setup.sh --verify

# Pull embedding model only
./setup.sh --pull-model

# Full setup with verification
./setup.sh
```

#### Windows (PowerShell)
The PowerShell setup script provides the same functionality:

```powershell
# Verify current setup
.\setup.ps1 -Verify

# Pull embedding model only
.\setup.ps1 -PullModel

# Full setup with verification
.\setup.ps1

# Show help
.\setup.ps1 -Help
```

## 🔍 Troubleshooting

### Common Issues

#### Services Won't Start

1. **Check Docker/Podman is running**:
   ```bash
   docker --version
   docker compose --version
   # or
   podman --version
   podman compose version
   ```

2. **Check port conflicts**:
   ```bash
   # Check if ports are in use
   netstat -an | grep 6333
   netstat -an | grep 11434
   ```

3. **Check available memory**:
   ```bash
   free -h  # Linux
   # Ensure you have enough RAM for your chosen model
   ```

#### Ollama Model Issues

1. **Model not found**:
   ```bash
   # Pull model manually with Docker
   docker exec roo-ollama ollama pull nomic-embed-text
   
   # Pull model manually with Podman
   podman exec roo-ollama ollama pull nomic-embed-text
   ```

2. **Out of memory errors**:
   - Reduce `OLLAMA_MEMORY_LIMIT` in `.env`
   - Switch to `nomic-embed-text` model
   - Close other applications

#### Qdrant Connection Issues

1. **Check Qdrant logs**:
   ```bash
   # Docker
   docker compose logs qdrant
   
   # Podman
   podman compose logs qdrant
   ```

2. **Reset Qdrant data**:
   ```bash
   # Docker
   docker compose down
   rm -rf ./data/qdrant
   docker compose up -d
   
   # Podman
   podman compose down
   rm -rf ./data/qdrant
   podman compose up -d
   ```

#### Podman-Specific Issues

1. **Permission errors or cgroup issues**:
   ```bash
   # Enable lingering for user services
   loginctl enable-linger $USER
   
   # Start podman socket
   systemctl --user enable --now podman.socket
   
   # Set DOCKER_HOST for compose compatibility
   export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
   ```

2. **Compose provider warnings**:
   - Podman uses Docker's compose plugin for compatibility
   - Warning messages about "external compose provider" are normal
   - Functionality remains the same as Docker Compose

3. **Network connectivity issues**:
   ```bash
   # Check if services are bound to correct interfaces
   podman ps
   
   # Check podman system info
   podman system info
   ```

### Performance Optimization

1. **Increase memory limits** in `.env`:
   ```bash
   OLLAMA_MEMORY_LIMIT=32G
   QDRANT_MEMORY_LIMIT=8G
   ```

2. **Use SSD storage** for better I/O performance

3. **Enable GPU support** (NVIDIA only):
   ```bash
   # Uncomment GPU lines in docker-compose.yml
   # Ensure nvidia-docker is installed
   ```

### Logs and Monitoring

```bash
# View all logs - Docker
docker compose logs -f

# View all logs - Podman  
podman compose logs -f

# View specific service logs - Docker
docker compose logs -f qdrant
docker compose logs -f ollama

# View specific service logs - Podman
podman compose logs -f qdrant
podman compose logs -f ollama

# View resource usage - Docker
docker stats

# View resource usage - Podman
podman stats
```

## 🔧 Container Runtime Support

This setup supports both Docker and Podman as container runtimes. The setup scripts automatically detect which runtime is available and use the appropriate commands.

### Runtime Detection

The setup scripts detect container runtimes in the following order:

1. **Podman** - If `podman` is available and supports `podman compose`
2. **Docker** - If `docker` is available with either `docker compose` or `docker-compose`

### Manual Runtime Selection

You can also run containers manually:

```bash
# Using Docker
docker compose up -d
docker compose down

# Using Podman
podman compose up -d
podman compose down

# Using legacy docker-compose
docker-compose up -d
docker-compose down
```

### Compatibility

- The `docker-compose.yml` file is compatible with both Docker and Podman
- Environment variables work the same way in both runtimes
- Data persistence and networking function identically
- Health checks and resource limits are supported by both

## 🔧 Advanced Configuration

### GPU Support (NVIDIA)

1. Install [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)

2. Uncomment GPU configuration in `docker-compose.yml`:
   ```yaml
   runtime: nvidia
   environment:
     - NVIDIA_VISIBLE_DEVICES=all
   ```

3. Set `ENABLE_GPU=true` in `.env`

### Custom Network Configuration

The services use a custom Docker network `roo-code-indexing` for isolation. To connect external services:

```bash
# Connect another container to the network - Docker
docker network connect roo-code-indexing your-container-name

# Connect another container to the network - Podman
podman network connect roo-code-indexing your-container-name
```

### Scaling Considerations

For production deployments:

1. **Use external volumes** for better performance
2. **Configure resource limits** based on workload
3. **Set up monitoring** with Prometheus/Grafana
4. **Configure backup strategies** for data persistence

## 📚 API Documentation

### Qdrant API
- **Web UI**: http://localhost:6333/dashboard
- **API Docs**: http://localhost:6333/docs
- **Collections**: http://localhost:6333/collections

### Ollama API
- **Models**: http://localhost:11434/api/tags
- **Generate**: http://localhost:11434/api/generate
- **Embeddings**: http://localhost:11434/api/embeddings

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with both embedding models
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review Docker and Docker Compose logs
3. Ensure system requirements are met
4. Verify network connectivity and ports

For additional support, please create an issue with:
- System specifications
- Error messages
- Docker and Docker Compose versions
- Steps to reproduce the issue
