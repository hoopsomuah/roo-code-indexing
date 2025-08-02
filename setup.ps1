# Roo Code Indexing Docker Setup Script for Windows
# This PowerShell script automates the initial setup of Qdrant and Ollama services

param(
    [switch]$Help,
    [switch]$Verify,
    [switch]$PullModel
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-Status {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Function to check if command exists
function Test-Command {
    param([string]$Command)
    try {
        Get-Command $Command -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

# Function to check system requirements
function Test-Requirements {
    Write-Status "Checking system requirements..."
    
    # Check for container runtime (Podman or Docker)
    $script:ContainerRuntime = ""
    $script:ComposeCommand = @()
    $script:UsePods = $false
    
    # Check for Podman first
    if (Test-Command "podman") {
        Write-Status "Podman found, using native pod support..."
        $script:ContainerRuntime = "podman"
        $script:UsePods = $true
        Write-Success "Using Podman with Kubernetes pod support"
    }
    elseif (Test-Command "docker") {
        Write-Status "Docker found, checking if it's running..."
        try {
            docker version | Out-Null
        }
        catch {
            Write-Error "Docker is not running. Please start Docker Desktop."
            exit 1
        }
        
        # Check if Docker Compose is available
        $composeAvailable = $false
        if (Test-Command "docker-compose") {
            $composeAvailable = $true
            $script:ContainerRuntime = "docker"
            $script:ComposeCommand = @("docker-compose")
        }
        elseif ((docker compose version 2>$null) -ne $null) {
            $composeAvailable = $true
            $script:ContainerRuntime = "docker"
            $script:ComposeCommand = @("docker", "compose")
        }
        
        if (-not $composeAvailable) {
            Write-Error "Docker found but no compose support available. Please ensure Docker Desktop is properly installed."
            exit 1
        }
        
        $script:UsePods = $false
        Write-Success "Using Docker with compose support"
    }
    else {
        Write-Error "Neither Docker nor Podman is installed. Please install one of them first."
        Write-Host "Docker Desktop: https://www.docker.com/products/docker-desktop" -ForegroundColor Cyan
        Write-Host "Podman Desktop: https://podman-desktop.io/" -ForegroundColor Cyan
        exit 1
    }
    
    # Check available memory (Windows)
    try {
        $totalMemoryGB = [math]::Round((Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        Write-Status "Total system memory: $totalMemoryGB GB"
        
        if ($totalMemoryGB -lt 16) {
            Write-Warning "System has less than 16GB RAM. Consider using nomic-embed-text model."
        }
    }
    catch {
        Write-Warning "Could not determine system memory."
    }
    
    Write-Success "System requirements check passed"
}

# Function to create necessary directories
function New-DataDirectories {
    Write-Status "Creating data directories..."
    
    # Load environment variables if .env exists
    $envVars = @{}
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                $envVars[$matches[1]] = $matches[2]
            }
        }
    }
    
    # Create directories with defaults
    $qdrantDir = if ($envVars["QDRANT_STORAGE_PATH"]) { $envVars["QDRANT_STORAGE_PATH"] } else { ".\data\qdrant" }
    $ollamaDir = if ($envVars["OLLAMA_MODELS_PATH"]) { $envVars["OLLAMA_MODELS_PATH"] } else { ".\data\ollama" }
    
    New-Item -ItemType Directory -Path $qdrantDir -Force | Out-Null
    New-Item -ItemType Directory -Path $ollamaDir -Force | Out-Null
    
    Write-Success "Data directories created: $qdrantDir, $ollamaDir"
}

# Function to generate Kubernetes YAML with environment variables
function New-PodYaml {
    Write-Status "Generating Kubernetes pod configuration..."
    
    # Load environment variables if .env exists
    $envVars = @{}
    if (Test-Path ".env") {
        Get-Content ".env" | ForEach-Object {
            if ($_ -match "^([^#][^=]+)=(.*)$") {
                $envVars[$matches[1]] = $matches[2]
            }
        }
    }
    
    # Set defaults
    $qdrantPort = if ($envVars["QDRANT_PORT"]) { $envVars["QDRANT_PORT"] } else { "6333" }
    $qdrantGrpcPort = if ($envVars["QDRANT_GRPC_PORT"]) { $envVars["QDRANT_GRPC_PORT"] } else { "6334" }
    $qdrantLogLevel = if ($envVars["QDRANT_LOG_LEVEL"]) { $envVars["QDRANT_LOG_LEVEL"] } else { "INFO" }
    $qdrantMemoryLimit = if ($envVars["QDRANT_MEMORY_LIMIT"]) { $envVars["QDRANT_MEMORY_LIMIT"] } else { "4G" }
    $qdrantMemoryReservation = if ($envVars["QDRANT_MEMORY_RESERVATION"]) { $envVars["QDRANT_MEMORY_RESERVATION"] } else { "2G" }
    $qdrantStoragePath = if ($envVars["QDRANT_STORAGE_PATH"]) { $envVars["QDRANT_STORAGE_PATH"] } else { ".\data\qdrant" }
    
    $ollamaPort = if ($envVars["OLLAMA_PORT"]) { $envVars["OLLAMA_PORT"] } else { "11434" }
    $ollamaMemoryLimit = if ($envVars["OLLAMA_MEMORY_LIMIT"]) { $envVars["OLLAMA_MEMORY_LIMIT"] } else { "24G" }
    $ollamaMemoryReservation = if ($envVars["OLLAMA_MEMORY_RESERVATION"]) { $envVars["OLLAMA_MEMORY_RESERVATION"] } else { "16G" }
    $ollamaModelsPath = if ($envVars["OLLAMA_MODELS_PATH"]) { $envVars["OLLAMA_MODELS_PATH"] } else { ".\data\ollama" }
    
    # Convert memory limits to Kubernetes format
    $qdrantMemLimitK8s = $qdrantMemoryLimit -replace 'G$', 'Gi'
    $qdrantMemReqK8s = $qdrantMemoryReservation -replace 'G$', 'Gi'
    $ollamaMemLimitK8s = $ollamaMemoryLimit -replace 'G$', 'Gi'
    $ollamaMemReqK8s = $ollamaMemoryReservation -replace 'G$', 'Gi'
    
    # Get absolute paths
    $qdrantAbsPath = (Resolve-Path $qdrantStoragePath -ErrorAction SilentlyContinue).Path
    if (-not $qdrantAbsPath) { $qdrantAbsPath = (New-Item -ItemType Directory -Path $qdrantStoragePath -Force).FullName }
    
    $ollamaAbsPath = (Resolve-Path $ollamaModelsPath -ErrorAction SilentlyContinue).Path  
    if (-not $ollamaAbsPath) { $ollamaAbsPath = (New-Item -ItemType Directory -Path $ollamaModelsPath -Force).FullName }
    
    # Convert Windows paths to Unix-style for Podman
    $qdrantUnixPath = $qdrantAbsPath -replace '\\', '/' -replace '^C:', '/c'
    $ollamaUnixPath = $ollamaAbsPath -replace '\\', '/' -replace '^C:', '/c'
    
$podYaml = @"
# Kubernetes Pod definition for Roo Code Indexing  
# Generated automatically by setup.ps1
apiVersion: v1
kind: Pod
metadata:
  name: roo-code-indexing
  labels:
    app: roo-code-indexing
spec:
  restartPolicy: Always
  
  containers:
  # Qdrant vector database
  - name: qdrant
    image: qdrant/qdrant:latest
    ports:
    - containerPort: 6333
      hostPort: $qdrantPort
      protocol: TCP
    - containerPort: 6334
      hostPort: $qdrantGrpcPort
      protocol: TCP
    env:
    - name: QDRANT__SERVICE__HTTP_PORT
      value: "6333"
    - name: QDRANT__SERVICE__GRPC_PORT
      value: "6334"
    - name: QDRANT__LOG_LEVEL
      value: "$qdrantLogLevel"
    volumeMounts:
    - name: qdrant-storage
      mountPath: /qdrant/storage
    resources:
      limits:
        memory: "$qdrantMemLimitK8s"
      requests:
        memory: "$qdrantMemReqK8s"
    livenessProbe:
      httpGet:
        path: /health
        port: 6333
      initialDelaySeconds: 40
      periodSeconds: 30
      timeoutSeconds: 10
      failureThreshold: 3

  # Ollama LLM service
  - name: ollama
    image: ollama/ollama:latest
    ports:
    - containerPort: 11434
      hostPort: $ollamaPort
      protocol: TCP
    env:
    - name: OLLAMA_HOST
      value: "0.0.0.0"
    - name: OLLAMA_ORIGINS
      value: "*"
    volumeMounts:
    - name: ollama-models
      mountPath: /root/.ollama
    resources:
      limits:
        memory: "$ollamaMemLimitK8s"
      requests:
        memory: "$ollamaMemReqK8s"
    livenessProbe:
      httpGet:
        path: /api/tags
        port: 11434
      initialDelaySeconds: 60
      periodSeconds: 30
      timeoutSeconds: 10
      failureThreshold: 3

  volumes:
  - name: qdrant-storage
    hostPath:
      path: $qdrantUnixPath
      type: DirectoryOrCreate
  - name: ollama-models
    hostPath:
      path: $ollamaUnixPath
      type: DirectoryOrCreate
"@
    
    Set-Content -Path "pod.yaml" -Value $podYaml
    Write-Success "Generated pod.yaml with environment-specific configuration"
}
function Initialize-EnvFile {
    if (-not (Test-Path ".env")) {
        Write-Status "Creating .env file from template..."
        Copy-Item ".env.example" ".env"
        Write-Success ".env file created. Please review and modify as needed."
        Write-Warning "You may want to edit .env to choose your preferred embedding model."
    }
    else {
        Write-Status ".env file already exists, skipping creation."
    }
}

# Function to start services
function Start-Services {
    Write-Status "Starting $script:ContainerRuntime services..."
    
    if ($script:UsePods) {
        # Podman: Use Kubernetes pods
        Write-Status "Pulling images and starting pod..."
        
        # Generate pod configuration with current environment
        New-PodYaml
        
        # Pull images first
        Write-Status "Pulling container images..."
        podman pull qdrant/qdrant:latest
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to pull Qdrant image"
            exit 1
        }
        
        podman pull ollama/ollama:latest
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to pull Ollama image"
            exit 1
        }
        
        # Start the pod using Kubernetes YAML
        Write-Status "Starting pod with Kubernetes configuration..."
        podman play kube pod.yaml
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start pod"
            exit 1
        }
        
        Write-Success "Pod started successfully"
    }
    else {
        # Docker: Use Docker Compose
        Write-Status "Pulling images..."
        & $script:ComposeCommand[0] $script:ComposeCommand[1..($script:ComposeCommand.Length-1)] pull
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to pull container images"
            exit 1
        }
        
        # Start services
        Write-Status "Starting services in detached mode..."
        & $script:ComposeCommand[0] $script:ComposeCommand[1..($script:ComposeCommand.Length-1)] up -d
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to start services"
            exit 1
        }
        
        Write-Success "Services started successfully"
    }
}

# Function to wait for services to be healthy
function Wait-ForServices {
    Write-Status "Waiting for services to become healthy..."
    
    # Wait for Qdrant
    Write-Status "Checking Qdrant health..."
    $qdrantHealthy = $false
    for ($i = 1; $i -le 30; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:6333/health" -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Success "Qdrant is healthy"
                $qdrantHealthy = $true
                break
            }
        }
        catch {
            # Continue waiting
        }
        
        if ($i -eq 30) {
            Write-Error "Qdrant failed to become healthy"
            exit 1
        }
        Start-Sleep -Seconds 2
    }
    
    # Wait for Ollama
    Write-Status "Checking Ollama health..."
    $ollamaHealthy = $false
    for ($i = 1; $i -le 30; $i++) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -UseBasicParsing -TimeoutSec 5
            if ($response.StatusCode -eq 200) {
                Write-Success "Ollama is healthy"
                $ollamaHealthy = $true
                break
            }
        }
        catch {
            # Continue waiting
        }
        
        if ($i -eq 30) {
            Write-Error "Ollama failed to become healthy"
            exit 1
        }
        Start-Sleep -Seconds 2
    }
}

# Function to pull embedding model
function Get-EmbeddingModel {
    # Load environment variables
    $model = "nomic-embed-text"  # default
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $modelLine = $envContent | Where-Object { $_ -match "^EMBEDDING_MODEL=(.+)$" }
        if ($modelLine) {
            $model = $matches[1]
        }
    }
    
    Write-Status "Pulling embedding model: $model"
    Write-Warning "This may take several minutes depending on your internet connection..."
    
    # Pull the model using Ollama API
    try {
        if ($script:UsePods) {
            # Podman pod: container name includes pod name prefix
            podman exec roo-code-indexing-ollama ollama pull $model
        }
        else {
            # Docker compose: use standalone container name
            if ($script:ContainerRuntime -eq "podman") {
                podman exec roo-ollama ollama pull $model
            } else {
                docker exec roo-ollama ollama pull $model
            }
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Container exec failed"
        }
    }
    catch {
        Write-Error "Failed to pull embedding model: $model"
        Write-Error "Please check your internet connection and try again"
        exit 1
    }
    
    Write-Success "Embedding model $model pulled successfully"
}

# Function to verify setup
function Test-Setup {
    Write-Status "Verifying setup..."
    
    # Check if services are running
    if ($script:UsePods) {
        # Podman pod: check pod and containers
        $podExists = podman pod exists roo-code-indexing 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Roo Code Indexing pod is not running"
            return $false
        }
        
        $qdrantRunning = podman ps --filter "name=roo-code-indexing-qdrant" --format "{{.Names}}" | Select-String "roo-code-indexing-qdrant"
        $ollamaRunning = podman ps --filter "name=roo-code-indexing-ollama" --format "{{.Names}}" | Select-String "roo-code-indexing-ollama"
        
        if (-not $qdrantRunning) {
            Write-Error "Qdrant container is not running in pod"
            return $false
        }
        
        if (-not $ollamaRunning) {
            Write-Error "Ollama container is not running in pod"
            return $false
        }
    }
    else {
        # Docker compose: check individual containers
        if ($script:ContainerRuntime -eq "podman") {
            $qdrantRunning = podman ps --filter "name=roo-qdrant" --format "{{.Names}}" | Select-String "roo-qdrant"
            $ollamaRunning = podman ps --filter "name=roo-ollama" --format "{{.Names}}" | Select-String "roo-ollama"
        } else {
            $qdrantRunning = docker ps --filter "name=roo-qdrant" --format "{{.Names}}" | Select-String "roo-qdrant"
            $ollamaRunning = docker ps --filter "name=roo-ollama" --format "{{.Names}}" | Select-String "roo-ollama"
        }
        
        if (-not $qdrantRunning) {
            Write-Error "Qdrant container is not running"
            return $false
        }
        
        if (-not $ollamaRunning) {
            Write-Error "Ollama container is not running"
            return $false
        }
    }
    
    # Check if model is available
    $model = "nomic-embed-text"  # default
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $modelLine = $envContent | Where-Object { $_ -match "^EMBEDDING_MODEL=(.+)$" }
        if ($modelLine) {
            $model = $matches[1]
        }
    }
    
    try {
        if ($script:UsePods) {
            $modelList = podman exec roo-code-indexing-ollama ollama list
        }
        else {
            if ($script:ContainerRuntime -eq "podman") {
                $modelList = podman exec roo-ollama ollama list
            } else {
                $modelList = docker exec roo-ollama ollama list
            }
        }
        if (-not ($modelList | Select-String $model)) {
            Write-Warning "Embedding model $model not found in Ollama"
            return $false
        }
    }
    catch {
        Write-Warning "Could not verify embedding model"
        return $false
    }
    
    Write-Success "Setup verification completed successfully"
    return $true
}

# Function to display status
function Show-Status {
    Write-Host ""
    Write-Success "=== Roo Code Indexing Setup Complete ==="
    Write-Host ""
    Write-Host "Services:" -ForegroundColor Cyan
    Write-Host "  • Qdrant: http://localhost:6333" -ForegroundColor White
    Write-Host "  • Ollama: http://localhost:11434" -ForegroundColor White
    Write-Host ""
    Write-Host "Data directories:" -ForegroundColor Cyan
    
    $qdrantDir = ".\data\qdrant"
    $ollamaDir = ".\data\ollama"
    if (Test-Path ".env") {
        $envContent = Get-Content ".env"
        $qdrantLine = $envContent | Where-Object { $_ -match "^QDRANT_STORAGE_PATH=(.+)$" }
        $ollamaLine = $envContent | Where-Object { $_ -match "^OLLAMA_MODELS_PATH=(.+)$" }
        if ($qdrantLine) { $qdrantDir = $matches[1] }
        if ($ollamaLine) { $ollamaDir = $matches[1] }
    }
    
    Write-Host "  • Qdrant: $qdrantDir" -ForegroundColor White
    Write-Host "  • Ollama: $ollamaDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Management commands:" -ForegroundColor Cyan
    
    if ($script:UsePods) {
        Write-Host "  • Stop pod: podman pod stop roo-code-indexing" -ForegroundColor White
        Write-Host "  • Remove pod: podman pod rm roo-code-indexing" -ForegroundColor White
        Write-Host "  • View logs: podman pod logs roo-code-indexing" -ForegroundColor White
        Write-Host "  • Restart pod: podman pod restart roo-code-indexing" -ForegroundColor White
    }
    else {
        $commandString = $script:ComposeCommand -join " "
        Write-Host "  • Stop services: $commandString down" -ForegroundColor White
        Write-Host "  • View logs: $commandString logs -f" -ForegroundColor White
        Write-Host "  • Restart: $commandString restart" -ForegroundColor White
    }
    Write-Host ""
}

# Function to show help
function Show-Help {
    Write-Host "Roo Code Indexing Docker Setup for Windows" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: .\setup.ps1 [OPTIONS]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Help          Show this help message" -ForegroundColor White
    Write-Host "  -Verify        Only verify the current setup" -ForegroundColor White
    Write-Host "  -PullModel     Only pull the embedding model" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\setup.ps1                 # Full setup" -ForegroundColor White
    Write-Host "  .\setup.ps1 -Verify         # Verify current setup" -ForegroundColor White
    Write-Host "  .\setup.ps1 -PullModel      # Pull embedding model only" -ForegroundColor White
    Write-Host ""
}

# Main execution function
function Invoke-Main {
    Write-Host "=== Roo Code Indexing Docker Setup ===" -ForegroundColor Green
    Write-Host ""
    
    Test-Requirements
    Initialize-EnvFile
    New-DataDirectories
    Start-Services
    Wait-ForServices
    
    # Try to pull the embedding model
    try {
        Get-EmbeddingModel
        if (Test-Setup) {
            Show-Status
        }
        else {
            Write-Warning "Setup completed but verification had issues. Please check the logs."
        }
    }
    catch {
        Write-Warning "Setup completed but failed to pull embedding model. You can pull it manually later."
        Show-Status
    }
}

# Handle script parameters
if ($Help) {
    Show-Help
    exit 0
}
elseif ($Verify) {
    Test-Requirements
    $result = Test-Setup
    exit $(if ($result) { 0 } else { 1 })
}
elseif ($PullModel) {
    Test-Requirements
    Get-EmbeddingModel
    exit 0
}
else {
    Invoke-Main
}