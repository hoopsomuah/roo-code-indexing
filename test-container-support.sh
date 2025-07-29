#!/bin/bash

# Comprehensive test for both Docker and Podman support in Roo Code Indexing setup

set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Function to test container runtime
test_runtime() {
    local runtime=$1
    local compose_cmd=$2
    
    print_status "Testing $runtime with '$compose_cmd'"
    
    # Clean up any existing containers
    $compose_cmd down -v &>/dev/null || true
    
    # Start services
    print_status "Starting services with $runtime..."
    if ! $compose_cmd up -d; then
        print_error "Failed to start services with $runtime"
        return 1
    fi
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    local max_attempts=30
    local attempt=0
    
    # Check Qdrant
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:6333/health >/dev/null 2>&1; then
            print_success "Qdrant is responding"
            break
        fi
        if [ $attempt -eq $((max_attempts - 1)) ]; then
            print_error "Qdrant failed to become ready after $max_attempts attempts"
            $compose_cmd logs qdrant
            return 1
        fi
        sleep 2
        ((attempt++))
    done
    
    # Check Ollama
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
            print_success "Ollama is responding"
            break
        fi
        if [ $attempt -eq $((max_attempts - 1)) ]; then
            print_error "Ollama failed to become ready after $max_attempts attempts"
            $compose_cmd logs ollama
            return 1
        fi
        sleep 2
        ((attempt++))
    done
    
    # Test API endpoints
    print_status "Testing API endpoints..."
    
    # Test Qdrant collections endpoint
    if curl -s http://localhost:6333/collections | grep -q "result"; then
        print_success "Qdrant collections API working"
    else
        print_warning "Qdrant collections API returned unexpected response"
    fi
    
    # Test Ollama tags endpoint
    if curl -s http://localhost:11434/api/tags | grep -q "models"; then
        print_success "Ollama tags API working"
    else
        print_warning "Ollama tags API returned unexpected response"
    fi
    
    # Clean up
    print_status "Cleaning up $runtime test..."
    $compose_cmd down -v
    
    print_success "$runtime test completed successfully"
    return 0
}

# Main test function
main() {
    echo "=============================================="
    echo "  Roo Code Indexing Container Runtime Tests"
    echo "=============================================="
    echo
    
    # Ensure we have a .env file
    if [ ! -f .env ]; then
        cp .env.example .env
        print_status "Created .env file for testing"
    fi
    
    local docker_available=false
    local podman_available=false
    local tests_passed=0
    local tests_failed=0
    
    # Check Docker availability
    if command -v docker >/dev/null 2>&1; then
        if docker compose version >/dev/null 2>&1; then
            docker_available=true
            print_status "Docker with compose support detected"
        elif command -v docker-compose >/dev/null 2>&1; then
            docker_available=true
            print_status "Docker with docker-compose detected"
        fi
    fi
    
    # Check Podman availability
    if command -v podman >/dev/null 2>&1; then
        if podman compose version >/dev/null 2>&1; then
            podman_available=true
            print_status "Podman with compose support detected"
        fi
    fi
    
    if [ "$docker_available" = false ] && [ "$podman_available" = false ]; then
        print_error "Neither Docker nor Podman with compose support is available"
        exit 1
    fi
    
    # Test Docker if available
    if [ "$docker_available" = true ]; then
        echo
        print_status "=== Testing Docker ==="
        if command -v docker-compose >/dev/null 2>&1; then
            compose_cmd="docker-compose"
        else
            compose_cmd="docker compose"
        fi
        
        if test_runtime "Docker" "$compose_cmd"; then
            ((tests_passed++))
        else
            ((tests_failed++))
        fi
    fi
    
    # Test Podman if available  
    if [ "$podman_available" = true ]; then
        echo
        print_status "=== Testing Podman ==="
        
        # Set up Podman environment
        export DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock
        
        if test_runtime "Podman" "podman compose"; then
            ((tests_passed++))
        else
            ((tests_failed++))
        fi
        
        unset DOCKER_HOST
    fi
    
    # Test setup script detection
    echo
    print_status "=== Testing Setup Script Detection ==="
    
    # Test that setup script detects the right runtime
    ./setup.sh --help >/dev/null
    if [ $? -eq 0 ]; then
        print_success "Setup script help works"
        ((tests_passed++))
    else
        print_error "Setup script help failed"
        ((tests_failed++))
    fi
    
    # Summary
    echo
    echo "=============================================="
    echo "  Test Results"
    echo "=============================================="
    print_success "Tests passed: $tests_passed"
    if [ $tests_failed -gt 0 ]; then
        print_error "Tests failed: $tests_failed"
        exit 1
    else
        print_success "All tests passed!"
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Test script for container runtime compatibility"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo
        exit 0
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