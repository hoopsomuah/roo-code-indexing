# Roo Code Indexing Podman Setup Script for Windows
# This PowerShell script automates the setup of Qdrant and Ollama services using Podman pods

param(
    [switch]$Help
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output with emojis
function Write-Status {
    param([string]$Message)
    Write-Host "🔵 [INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "✅ [SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "⚠️  [WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "❌ [ERROR] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
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

# Function to install Podman using winget
function Install-Podman {
    Write-Status "Podman not found. Installing Podman using winget..."
    
    # Check if winget is available
    if (-not (Test-Command "winget")) {
        Write-Error "winget is not available. Please install Podman manually from https://podman-desktop.io/"
        exit 1
    }
    
    try {
        Write-Status "Installing Podman Desktop..."
        winget install RedHat.Podman-Desktop
        if ($LASTEXITCODE -ne 0) {
            throw "winget install failed"
        }
        
        Write-Success "Podman Desktop installed successfully"
        Write-Warning "Please restart your terminal/PowerShell session and run this script again"
        Write-Info "If Podman is still not found, you may need to add it to your PATH"
        exit 0
    }
    catch {
        Write-Error "Failed to install Podman using winget: $_"
        Write-Info "Please install Podman manually from https://podman-desktop.io/"
        exit 1
    }
}

# Function to check system requirements and install Podman if needed
function Initialize-Requirements {
    Write-Status "Checking system requirements..."
    
    # Check for Podman, install if not found
    if (-not (Test-Command "podman")) {
        Install-Podman
        return
    }
    
    Write-Success "Podman found"
    
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
    
    # Check if template exists
    if (-not (Test-Path "pod.yaml.template")) {
        Write-Error "❌ pod.yaml.template not found! Please ensure the template file exists."
        exit 1
    }
    
    # Read template and substitute variables
    $templateContent = Get-Content "pod.yaml.template" -Raw
    $podYaml = $templateContent `
        -replace '{{QDRANT_PORT}}', $qdrantPort `
        -replace '{{QDRANT_GRPC_PORT}}', $qdrantGrpcPort `
        -replace '{{QDRANT_LOG_LEVEL}}', $qdrantLogLevel `
        -replace '{{QDRANT_MEM_LIMIT_K8S}}', $qdrantMemLimitK8s `
        -replace '{{QDRANT_MEM_REQ_K8S}}', $qdrantMemReqK8s `
        -replace '{{OLLAMA_PORT}}', $ollamaPort `
        -replace '{{OLLAMA_MEM_LIMIT_K8S}}', $ollamaMemLimitK8s `
        -replace '{{OLLAMA_MEM_REQ_K8S}}', $ollamaMemReqK8s `
        -replace '{{QDRANT_UNIX_PATH}}', $qdrantUnixPath `
        -replace '{{OLLAMA_UNIX_PATH}}', $ollamaUnixPath
    
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

# Function to check if system is already running
function Test-SystemRunning {
    try {
        # Check if pod exists and is running
        $podExists = podman pod exists roo-code-indexing 2>$null
        if ($LASTEXITCODE -eq 0) {
            $qdrantRunning = podman ps --filter "name=roo-code-indexing-qdrant" --format "{{.Names}}" | Select-String "roo-code-indexing-qdrant"
            $ollamaRunning = podman ps --filter "name=roo-code-indexing-ollama" --format "{{.Names}}" | Select-String "roo-code-indexing-ollama"
            
            if ($qdrantRunning -and $ollamaRunning) {
                return $true
            }
        }
        return $false
    }
    catch {
        return $false
    }
}

# Function to start services
function Start-Services {
    Write-Status "Starting Podman services..."
    
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
        podman exec roo-code-indexing-ollama ollama pull $model
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
        $modelList = podman exec roo-code-indexing-ollama ollama list
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
    Write-Success "🎉 Roo Code Indexing Podman Setup Complete 🎉"
    Write-Host ""
    Write-Info "🌐 Services:"
    Write-Host "  • Qdrant: http://localhost:6333" -ForegroundColor White
    Write-Host "  • Ollama: http://localhost:11434" -ForegroundColor White
    Write-Host ""
    Write-Info "💾 Data directories:"
    
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
    Write-Info "🛠️  Management commands:"
    Write-Host "  • Stop pod: podman pod stop roo-code-indexing" -ForegroundColor White
    Write-Host "  • Remove pod: podman pod rm roo-code-indexing" -ForegroundColor White
    Write-Host "  • View logs: podman pod logs roo-code-indexing" -ForegroundColor White
    Write-Host "  • Restart pod: podman pod restart roo-code-indexing" -ForegroundColor White
    Write-Host ""
}

# Function to show help
function Show-Help {
    Write-Host "🚀 Roo Code Indexing Podman Setup for Windows" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage: .\setup-podman.ps1 [OPTIONS]" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Cyan
    Write-Host "  -Help          Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  .\setup-podman.ps1           # Full idempotent setup" -ForegroundColor White
    Write-Host "  .\setup-podman.ps1 -Help     # Show this help" -ForegroundColor White
    Write-Host ""
    Write-Host "Features:" -ForegroundColor Cyan
    Write-Host "  ✅ Automatic Podman installation via winget" -ForegroundColor White
    Write-Host "  ✅ Idempotent - safe to run multiple times" -ForegroundColor White
    Write-Host "  ✅ Native Kubernetes pod support" -ForegroundColor White  
    Write-Host "  ✅ Status display when system is already running" -ForegroundColor White
    Write-Host ""
}

# Main execution function
function Invoke-Main {
    Write-Host "🚀 Roo Code Indexing Podman Setup 🚀" -ForegroundColor Green
    Write-Host ""
    
    # Check if system is already running
    if (Test-SystemRunning) {
        Write-Success "System is already running! Showing status..."
        Show-Status
        return
    }
    
    Initialize-Requirements
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
else {
    Invoke-Main
}