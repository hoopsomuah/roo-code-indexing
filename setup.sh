#!/bin/bash

# Roo Code Indexing Docker Setup Script
# This script automates the initial setup of Qdrant and Ollama services

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check for container runtime (Podman or Docker)
    CONTAINER_RUNTIME=""
    COMPOSE_CMD=""
    USE_PODS=""
    
    if command_exists podman; then
        print_status "Podman found, using native pod support..."
        CONTAINER_RUNTIME="podman"
        USE_PODS="true"
        print_success "Using Podman with Kubernetes pod support"
    elif command_exists docker; then
        print_status "Docker found, checking compose support..."
        if command_exists docker-compose; then
            CONTAINER_RUNTIME="docker"
            COMPOSE_CMD="docker-compose"
            USE_PODS="false"
            print_success "Using Docker with docker-compose"
        elif docker compose version >/dev/null 2>&1; then
            CONTAINER_RUNTIME="docker"
            COMPOSE_CMD="docker compose"
            USE_PODS="false"
            print_success "Using Docker with compose plugin"
        else
            print_error "Docker found but no compose support available"
            exit 1
        fi
    else
        print_error "Neither Docker nor Podman is installed. Please install one of them first."
        exit 1
    fi
    
    # Export for use by other functions
    export CONTAINER_RUNTIME
    export COMPOSE_CMD
    export USE_PODS
    
    # Check available memory
    if command_exists free; then
        TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
        if [ "$TOTAL_MEM" -lt 16 ]; then
            print_warning "System has less than 16GB RAM. Consider using nomic-embed-text model."
        fi
    fi
    
    print_success "System requirements check passed"
}

# Function to create necessary directories
create_directories() {
    print_status "Creating data directories..."
    
    # Load environment variables if .env exists
    if [ -f .env ]; then
        source .env
    fi
    
    # Create directories with defaults
    QDRANT_DIR="${QDRANT_STORAGE_PATH:-./data/qdrant}"
    OLLAMA_DIR="${OLLAMA_MODELS_PATH:-./data/ollama}"
    
    mkdir -p "$QDRANT_DIR"
    mkdir -p "$OLLAMA_DIR"
    
    # Set proper permissions
    chmod 755 "$QDRANT_DIR"
    chmod 755 "$OLLAMA_DIR"
    
    print_success "Data directories created: $QDRANT_DIR, $OLLAMA_DIR"
}

# Function to generate Kubernetes YAML with environment variables
generate_pod_yaml() {
    print_status "Generating Kubernetes pod configuration..."
    
    # Load environment variables if .env exists
    local qdrant_port="${QDRANT_PORT:-6333}"
    local qdrant_grpc_port="${QDRANT_GRPC_PORT:-6334}"
    local qdrant_log_level="${QDRANT_LOG_LEVEL:-INFO}"
    local qdrant_memory_limit="${QDRANT_MEMORY_LIMIT:-4G}"
    local qdrant_memory_reservation="${QDRANT_MEMORY_RESERVATION:-2G}"
    local qdrant_storage_path="${QDRANT_STORAGE_PATH:-./data/qdrant}"
    
    local ollama_port="${OLLAMA_PORT:-11434}"
    local ollama_memory_limit="${OLLAMA_MEMORY_LIMIT:-24G}"
    local ollama_memory_reservation="${OLLAMA_MEMORY_RESERVATION:-16G}"
    local ollama_models_path="${OLLAMA_MODELS_PATH:-./data/ollama}"
    
    # Convert memory limits to Kubernetes format (G -> Gi)
    local qdrant_mem_limit_k8s=$(echo "$qdrant_memory_limit" | sed 's/G$/Gi/')
    local qdrant_mem_req_k8s=$(echo "$qdrant_memory_reservation" | sed 's/G$/Gi/')
    local ollama_mem_limit_k8s=$(echo "$ollama_memory_limit" | sed 's/G$/Gi/')
    local ollama_mem_req_k8s=$(echo "$ollama_memory_reservation" | sed 's/G$/Gi/')
    
    # Get absolute paths for volume mounts
    local qdrant_abs_path=$(realpath "$qdrant_storage_path")
    local ollama_abs_path=$(realpath "$ollama_models_path")
    
    cat > pod.yaml << EOF
# Kubernetes Pod definition for Roo Code Indexing
# Generated automatically by setup.sh
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
      hostPort: $qdrant_port
      protocol: TCP
    - containerPort: 6334
      hostPort: $qdrant_grpc_port
      protocol: TCP
    env:
    - name: QDRANT__SERVICE__HTTP_PORT
      value: "6333"
    - name: QDRANT__SERVICE__GRPC_PORT
      value: "6334"  
    - name: QDRANT__LOG_LEVEL
      value: "$qdrant_log_level"
    volumeMounts:
    - name: qdrant-storage
      mountPath: /qdrant/storage
    resources:
      limits:
        memory: "$qdrant_mem_limit_k8s"
      requests:
        memory: "$qdrant_mem_req_k8s"
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
      hostPort: $ollama_port
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
        memory: "$ollama_mem_limit_k8s"
      requests:
        memory: "$ollama_mem_req_k8s"
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
      path: $qdrant_abs_path
      type: DirectoryOrCreate
  - name: ollama-models
    hostPath:
      path: $ollama_abs_path
      type: DirectoryOrCreate
EOF
    
    print_success "Generated pod.yaml with environment-specific configuration"
}
setup_env_file() {
    if [ ! -f .env ]; then
        print_status "Creating .env file from template..."
        cp .env.example .env
        print_success ".env file created. Please review and modify as needed."
        print_warning "You may want to edit .env to choose your preferred embedding model."
    else
        print_status ".env file already exists, skipping creation."
    fi
}

# Function to start services
start_services() {
    print_status "Starting $CONTAINER_RUNTIME services..."
    
    if [ "$USE_PODS" = "true" ]; then
        # Podman: Use Kubernetes pods
        print_status "Pulling images and starting pod..."
        
        # Generate pod configuration with current environment
        if [ -f .env ]; then
            source .env
        fi
        generate_pod_yaml
        
        # Pull images first
        print_status "Pulling container images..."
        podman pull qdrant/qdrant:latest
        podman pull ollama/ollama:latest
        
        # Start the pod using Kubernetes YAML
        print_status "Starting pod with Kubernetes configuration..."
        podman play kube pod.yaml
        
        print_success "Pod started successfully"
    else
        # Docker: Use Docker Compose
        print_status "Pulling images..."
        $COMPOSE_CMD pull
        
        # Start services
        print_status "Starting services in detached mode..."
        $COMPOSE_CMD up -d
        
        print_success "Services started successfully"
    fi
}

# Function to wait for services to be healthy
wait_for_services() {
    print_status "Waiting for services to become healthy..."
    
    # Wait for Qdrant
    print_status "Checking Qdrant health..."
    for i in {1..30}; do
        if curl -s http://localhost:6333/health >/dev/null 2>&1; then
            print_success "Qdrant is healthy"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "Qdrant failed to become healthy"
            exit 1
        fi
        sleep 2
    done
    
    # Wait for Ollama
    print_status "Checking Ollama health..."
    for i in {1..30}; do
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            print_success "Ollama is healthy"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "Ollama failed to become healthy"
            exit 1
        fi
        sleep 2
    done
}

# Function to pull embedding model
pull_embedding_model() {
    # Load environment variables
    if [ -f .env ]; then
        source .env
    fi
    
    MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
    
    print_status "Pulling embedding model: $MODEL"
    print_warning "This may take several minutes depending on your internet connection..."
    
    # Pull the model using Ollama API
    if [ "$USE_PODS" = "true" ]; then
        # Podman pod: container name includes pod name prefix
        if ! podman exec roo-code-indexing-ollama ollama pull "$MODEL"; then
            print_error "Failed to pull embedding model: $MODEL"
            print_error "Please check your internet connection and try again"
            exit 1
        fi
    else
        # Docker compose: use standalone container name
        if ! $CONTAINER_RUNTIME exec roo-ollama ollama pull "$MODEL"; then
            print_error "Failed to pull embedding model: $MODEL"
            print_error "Please check your internet connection and try again"
            exit 1
        fi
    fi
    
    print_success "Embedding model $MODEL pulled successfully"
}

# Function to verify setup
verify_setup() {
    print_status "Verifying setup..."
    
    # Check if services are running
    if [ "$USE_PODS" = "true" ]; then
        # Podman pod: check pod and containers
        if ! podman pod exists roo-code-indexing; then
            print_error "Roo Code Indexing pod is not running"
            exit 1
        fi
        
        if ! podman ps | grep -q roo-code-indexing-qdrant; then
            print_error "Qdrant container is not running in pod"
            exit 1
        fi
        
        if ! podman ps | grep -q roo-code-indexing-ollama; then
            print_error "Ollama container is not running in pod"
            exit 1
        fi
    else
        # Docker compose: check individual containers
        if ! $CONTAINER_RUNTIME ps | grep -q roo-qdrant; then
            print_error "Qdrant container is not running"
            exit 1
        fi
        
        if ! $CONTAINER_RUNTIME ps | grep -q roo-ollama; then
            print_error "Ollama container is not running"
            exit 1
        fi
    fi
    
    # Check if model is available
    if [ -f .env ]; then
        source .env
    fi
    MODEL="${EMBEDDING_MODEL:-nomic-embed-text}"
    
    if [ "$USE_PODS" = "true" ]; then
        if ! podman exec roo-code-indexing-ollama ollama list | grep -q "$MODEL"; then
            print_warning "Embedding model $MODEL not found in Ollama"
            return 1
        fi
    else
        if ! $CONTAINER_RUNTIME exec roo-ollama ollama list | grep -q "$MODEL"; then
            print_warning "Embedding model $MODEL not found in Ollama"
            return 1
        fi
    fi
    
    print_success "Setup verification completed successfully"
    return 0
}

# Function to display status
show_status() {
    echo
    print_success "=== Roo Code Indexing Setup Complete ==="
    echo
    echo "Services:"
    echo "  • Qdrant: http://localhost:6333"
    echo "  • Ollama: http://localhost:11434"
    echo
    echo "Data directories:"
    if [ -f .env ]; then
        source .env
    fi
    echo "  • Qdrant: ${QDRANT_STORAGE_PATH:-./data/qdrant}"
    echo "  • Ollama: ${OLLAMA_MODELS_PATH:-./data/ollama}"
    echo
    echo "Management commands:"
    if [ "$USE_PODS" = "true" ]; then
        echo "  • Stop pod: podman pod stop roo-code-indexing"
        echo "  • Remove pod: podman pod rm roo-code-indexing"
        echo "  • View logs: podman pod logs roo-code-indexing"
        echo "  • Restart pod: podman pod restart roo-code-indexing"
    else
        echo "  • Stop services: $COMPOSE_CMD down"
        echo "  • View logs: $COMPOSE_CMD logs -f"
        echo "  • Restart: $COMPOSE_CMD restart"
    fi
    echo
}

# Main execution
main() {
    echo "=== Roo Code Indexing Docker Setup ==="
    echo
    
    check_requirements
    setup_env_file
    create_directories
    start_services
    wait_for_services
    
    # Try to pull the embedding model
    if pull_embedding_model; then
        if verify_setup; then
            show_status
        else
            print_warning "Setup completed but verification had issues. Please check the logs."
        fi
    else
        print_warning "Setup completed but failed to pull embedding model. You can pull it manually later."
        show_status
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --verify       Only verify the current setup"
        echo "  --pull-model   Only pull the embedding model"
        echo
        exit 0
        ;;
    --verify)
        verify_setup
        exit $?
        ;;
    --pull-model)
        pull_embedding_model
        exit $?
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac