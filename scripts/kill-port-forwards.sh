#!/bin/bash
set -euo pipefail

# Script to kill processes using common port-forward ports
# Usage: ./scripts/kill-port-forwards.sh [port1] [port2] ...
#        ./scripts/kill-port-forwards.sh --all (kills common ports)
#        ./scripts/kill-port-forwards.sh 3000 9090 (kills specific ports)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}✓${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo_error() {
    echo -e "${RED}✗${NC} $1"
}

echo_step() {
    echo -e "${BLUE}→${NC} $1"
}

# Common port-forward ports
COMMON_PORTS=(3000 9090 8080 8081 3100 3200 4317 4318 8443)

# Function to find process using a port
find_port_process() {
    local port=$1
    local os_type=$(uname -s)
    
    if [[ "$os_type" == "Darwin" ]]; then
        # macOS
        lsof -ti :${port} 2>/dev/null || true
    elif [[ "$os_type" == "Linux" ]]; then
        # Linux
        lsof -ti :${port} 2>/dev/null || fuser ${port}/tcp 2>/dev/null | awk '{print $1}' || true
    else
        echo_error "Unsupported OS: $os_type"
        return 1
    fi
}

# Function to get process info
get_process_info() {
    local pid=$1
    ps -p ${pid} -o pid=,command= 2>/dev/null | awk '{$1=$1; print}' || echo "Process ${pid} (already terminated)"
}

# Function to kill process on a port
kill_port() {
    local port=$1
    local pids=$(find_port_process ${port})
    
    if [[ -z "${pids}" ]]; then
        echo_warn "No process found using port ${port}"
        return 0
    fi
    
    echo_step "Port ${port}:"
    for pid in ${pids}; do
        local info=$(get_process_info ${pid})
        echo "  PID ${pid}: ${info}"
    done
    
    # Kill the processes
    for pid in ${pids}; do
        if kill -0 ${pid} 2>/dev/null; then
            kill ${pid} 2>/dev/null && echo_info "  Killed PID ${pid}" || echo_warn "  Failed to kill PID ${pid}"
        fi
    done
}

# Function to kill all common ports
kill_all_common_ports() {
    echo_step "Killing processes on common port-forward ports:"
    for port in "${COMMON_PORTS[@]}"; do
        kill_port ${port}
    done
}

# Main
main() {
    echo "=========================================="
    echo "  Kill Port-Forward Processes"
    echo "=========================================="
    echo ""
    
    # Check if lsof is available
    if ! command -v lsof >/dev/null 2>&1; then
        echo_error "lsof is required but not installed."
        echo "Install it with:"
        echo "  macOS: brew install lsof"
        echo "  Linux: sudo apt-get install lsof (or yum install lsof)"
        exit 1
    fi
    
    # Parse arguments
    if [[ $# -eq 0 ]]; then
        echo_warn "No ports specified. Use --all for common ports or specify ports."
        echo ""
        echo "Usage:"
        echo "  $0 --all                    # Kill processes on common ports (3000, 9090, 8080, etc.)"
        echo "  $0 3000                     # Kill process on port 3000"
        echo "  $0 3000 9090 8080          # Kill processes on multiple ports"
        echo ""
        echo "Common ports: ${COMMON_PORTS[*]}"
        exit 1
    fi
    
    # Handle --all flag
    if [[ "$1" == "--all" ]]; then
        kill_all_common_ports
    else
        # Kill specified ports
        echo_step "Killing processes on specified ports:"
        for port in "$@"; do
            # Validate port is a number
            if ! [[ "$port" =~ ^[0-9]+$ ]]; then
                echo_error "Invalid port: ${port} (must be a number)"
                continue
            fi
            
            if [[ ${port} -lt 1 || ${port} -gt 65535 ]]; then
                echo_error "Invalid port: ${port} (must be between 1 and 65535)"
                continue
            fi
            
            kill_port ${port}
        done
    fi
    
    echo ""
    echo_info "Done!"
}

main "$@"
