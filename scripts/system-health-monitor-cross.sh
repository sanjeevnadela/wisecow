#!/bin/bash

# Cross-Platform System Health Monitoring Script
# Works on both Linux and macOS
# Monitors CPU, Memory, Disk Space, and Running Processes

set -euo pipefail

# Configuration
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=85
LOG_FILE="/tmp/system-health.log"
ALERT_FILE="/tmp/system-alerts.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
else
    OS="unknown"
fi

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    if [ "$level" = "ALERT" ]; then
        echo "[$timestamp] [$level] $message" >> "$ALERT_FILE"
    fi
}

# Function to check CPU usage (cross-platform)
check_cpu() {
    local cpu_usage
    
    if [ "$OS" = "macos" ]; then
        # macOS CPU usage
        cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
    elif [ "$OS" = "linux" ]; then
        # Linux CPU usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    # Remove decimal point if present
    cpu_usage=${cpu_usage%.*}
    
    if [ "$cpu_usage" -gt "$CPU_THRESHOLD" ]; then
        log_message "ALERT" "CPU usage is ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        return 1
    else
        log_message "INFO" "CPU usage: ${cpu_usage}%"
        return 0
    fi
}

# Function to check memory usage (cross-platform)
check_memory() {
    local mem_percent
    
    if [ "$OS" = "macos" ]; then
        # macOS memory usage
        mem_percent=$(vm_stat | perl -ne '/page size of (\d+)/ and $size=$1; /Pages\s+([^:]+)[^\d]+(\d+)/ and printf("%-16s % 16.2f MB\n", "$1:", $2 * $size / 1048576);' | grep "free:" | awk '{print $2}' | sed 's/MB//')
        # Get total and used memory differently for macOS
        local total_mem=$(sysctl -n hw.memsize)
        total_mem=$((total_mem / 1024 / 1024))  # Convert to MB
        local free_mem=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        free_mem=$((free_mem * 4096 / 1024 / 1024))  # Convert pages to MB
        local used_mem=$((total_mem - free_mem))
        mem_percent=$((used_mem * 100 / total_mem))
    elif [ "$OS" = "linux" ]; then
        # Linux memory usage
        local mem_info
        mem_info=$(free | grep Mem)
        local total_mem=$(echo $mem_info | awk '{print $2}')
        local used_mem=$(echo $mem_info | awk '{print $3}')
        mem_percent=$((used_mem * 100 / total_mem))
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    if [ "$mem_percent" -gt "$MEMORY_THRESHOLD" ]; then
        log_message "ALERT" "Memory usage is ${mem_percent}% (threshold: ${MEMORY_THRESHOLD}%)"
        return 1
    else
        log_message "INFO" "Memory usage: ${mem_percent}%"
        return 0
    fi
}

# Function to check disk space (cross-platform)
check_disk() {
    local disk_usage
    
    if [ "$OS" = "macos" ]; then
        # macOS disk usage
        disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    elif [ "$OS" = "linux" ]; then
        # Linux disk usage
        disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    if [ "$disk_usage" -gt "$DISK_THRESHOLD" ]; then
        log_message "ALERT" "Disk usage is ${disk_usage}% (threshold: ${DISK_THRESHOLD}%)"
        return 1
    else
        log_message "INFO" "Disk usage: ${disk_usage}%"
        return 0
    fi
}

# Function to check running processes (cross-platform)
check_processes() {
    local total_processes
    local zombie_processes
    
    if [ "$OS" = "macos" ]; then
        # macOS process count
        total_processes=$(ps aux | wc -l)
        zombie_processes=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    elif [ "$OS" = "linux" ]; then
        # Linux process count
        total_processes=$(ps aux | wc -l)
        zombie_processes=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    log_message "INFO" "Total processes: $total_processes, Zombie processes: $zombie_processes"
    
    if [ "$zombie_processes" -gt 10 ]; then
        log_message "ALERT" "High number of zombie processes: $zombie_processes"
        return 1
    fi
    
    return 0
}

# Function to get system load average (cross-platform)
check_load_average() {
    local load_avg
    local cpu_cores
    
    if [ "$OS" = "macos" ]; then
        # macOS load average
        load_avg=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        cpu_cores=$(sysctl -n hw.ncpu)
    elif [ "$OS" = "linux" ]; then
        # Linux load average
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
        cpu_cores=$(nproc)
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
    
    local load_threshold=$((cpu_cores * 2))
    
    # Convert load average to integer for comparison
    local load_int=${load_avg%.*}
    
    if [ "$load_int" -gt "$load_threshold" ]; then
        log_message "ALERT" "Load average is $load_avg (threshold: $load_threshold for $cpu_cores cores)"
        return 1
    else
        log_message "INFO" "Load average: $load_avg (CPU cores: $cpu_cores)"
        return 0
    fi
}

# Function to check network connectivity (cross-platform)
check_network() {
    local ping_host="8.8.8.8"
    
    if [ "$OS" = "macos" ]; then
        if ping -c 1 -W 1000 "$ping_host" >/dev/null 2>&1; then
            log_message "INFO" "Network connectivity: OK"
            return 0
        else
            log_message "ALERT" "Network connectivity: FAILED"
            return 1
        fi
    elif [ "$OS" = "linux" ]; then
        if ping -c 1 -W 1 "$ping_host" >/dev/null 2>&1; then
            log_message "INFO" "Network connectivity: OK"
            return 0
        else
            log_message "ALERT" "Network connectivity: FAILED"
            return 1
        fi
    else
        log_message "ERROR" "Unsupported OS: $OSTYPE"
        return 1
    fi
}

# Function to display system information
display_system_info() {
    echo -e "${BLUE}=== System Health Report ===${NC}"
    echo "Hostname: $(hostname)"
    
    if [ "$OS" = "macos" ]; then
        echo "Uptime: $(uptime | awk -F'up ' '{print $2}' | awk -F', load' '{print $1}')"
    elif [ "$OS" = "linux" ]; then
        echo "Uptime: $(uptime -p)"
    else
        echo "Uptime: $(uptime)"
    fi
    
    echo "Date: $(date)"
    echo "OS: $(uname -s) $(uname -r)"
    echo ""
}

# Function to display current metrics
display_current_metrics() {
    echo -e "${BLUE}=== Current System Metrics ===${NC}"
    
    # CPU
    local cpu_usage
    if [ "$OS" = "macos" ]; then
        cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | sed 's/%//')
    elif [ "$OS" = "linux" ]; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    fi
    cpu_usage=${cpu_usage%.*}
    echo -e "CPU Usage: ${cpu_usage}%"
    
    # Memory
    local mem_percent
    if [ "$OS" = "macos" ]; then
        local total_mem=$(sysctl -n hw.memsize)
        total_mem=$((total_mem / 1024 / 1024))
        local free_mem=$(vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        free_mem=$((free_mem * 4096 / 1024 / 1024))
        local used_mem=$((total_mem - free_mem))
        mem_percent=$((used_mem * 100 / total_mem))
    elif [ "$OS" = "linux" ]; then
        local mem_info
        mem_info=$(free | grep Mem)
        local total_mem=$(echo $mem_info | awk '{print $2}')
        local used_mem=$(echo $mem_info | awk '{print $3}')
        mem_percent=$((used_mem * 100 / total_mem))
    fi
    echo -e "Memory Usage: ${mem_percent}%"
    
    # Disk
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    echo -e "Disk Usage: ${disk_usage}"
    
    # Load Average
    local load_avg
    if [ "$OS" = "macos" ]; then
        load_avg=$(uptime | awk -F'load averages:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    elif [ "$OS" = "linux" ]; then
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    fi
    echo -e "Load Average: ${load_avg}"
    
    echo ""
}

# Main monitoring function
run_health_checks() {
    local alerts=0
    
    echo "Starting system health monitoring..."
    log_message "INFO" "System health monitoring started (OS: $OS)"
    
    display_system_info
    display_current_metrics
    
    echo -e "${BLUE}=== Health Checks ===${NC}"
    
    # Run all checks
    if ! check_cpu; then ((alerts++)); fi
    if ! check_memory; then ((alerts++)); fi
    if ! check_disk; then ((alerts++)); fi
    if ! check_processes; then ((alerts++)); fi
    if ! check_load_average; then ((alerts++)); fi
    if ! check_network; then ((alerts++)); fi
    
    echo ""
    echo -e "${BLUE}=== Summary ===${NC}"
    
    if [ "$alerts" -eq 0 ]; then
        echo -e "${GREEN}All systems healthy! No alerts triggered.${NC}"
        log_message "INFO" "All health checks passed"
    else
        echo -e "${RED}$alerts alert(s) triggered. Check logs for details.${NC}"
        log_message "ALERT" "$alerts health check(s) failed"
    fi
    
    echo ""
    echo "Log file: $LOG_FILE"
    echo "Alert file: $ALERT_FILE"
    
    return $alerts
}

# Function to run continuous monitoring
continuous_monitoring() {
    local interval=${1:-60}  # Default 60 seconds
    echo "Starting continuous monitoring (interval: ${interval}s)"
    echo "Press Ctrl+C to stop"
    
    while true; do
        run_health_checks
        sleep "$interval"
    done
}

# Function to show help
show_help() {
    echo "Cross-Platform System Health Monitoring Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --continuous [SEC]  Run continuous monitoring (default: 60 seconds)"
    echo "  -l, --log-file FILE     Specify log file (default: /tmp/system-health.log)"
    echo "  -t, --thresholds        Show current thresholds"
    echo ""
    echo "Examples:"
    echo "  $0                      # Run single health check"
    echo "  $0 -c 30               # Run continuous monitoring every 30 seconds"
    echo "  $0 -l /var/log/health  # Use custom log file"
    echo ""
    echo "Supported OS: macOS, Linux"
}

# Function to show thresholds
show_thresholds() {
    echo "Current Alert Thresholds:"
    echo "  CPU Usage: ${CPU_THRESHOLD}%"
    echo "  Memory Usage: ${MEMORY_THRESHOLD}%"
    echo "  Disk Usage: ${DISK_THRESHOLD}%"
    echo "  Zombie Processes: 10"
    echo "  Load Average: 2x CPU cores"
    echo "  OS Detected: $OS"
}

# Main script logic
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--continuous)
                continuous_monitoring "${2:-60}"
                exit 0
                ;;
            -l|--log-file)
                LOG_FILE="$2"
                ALERT_FILE="${2%.*}-alerts.log"
                shift 2
                ;;
            -t|--thresholds)
                show_thresholds
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Run single health check
    run_health_checks
}

# Run main function with all arguments
main "$@"
