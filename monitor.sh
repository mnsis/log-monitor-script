#!/bin/bash

# Define variables
service_name="stationd"
log_file="/tmp/stationd_monitor.log"
error_patterns=(
    "account sequence mismatch"
    "Failed to get transaction by hash"
    "request ratelimited"
    "\[GIN\] .* \| 404 \|"
    "Failed to Init VRF"
    "incorrect pod number"
    "error unmarshalling: invalid character '<' looking for beginning of value"
    "VRF record is nil"
    "insufficient funds"
    "spendable balance .* is smaller than .*: insufficient funds"
)
critical_error_patterns=(
    "Failed to Validate VRF"
    "Rollback required"
    "Failed to Transact Verify pod"
)
rpc_error_patterns=(
    "error unmarshalling: invalid character '<'"
    "insufficient fees"
)
additional_error_patterns=(
    "Client connection error: error while requesting node"
    "Error in getting sender balance : http post error: Post"
    "Switchyard client connection error"
)
persistent_error_patterns=(
    "Failed to get transaction by hash: not found"
    "failed to disperse blob error"
    "TxError: Pod not submitted"
    "spendable balance .* is smaller than .*: insufficient funds"
)
rpc_endpoints=(
    "https://t-airchains.rpc.utsa.tech/"
    "https://testnet.rpc.airchains.silentvalidator.com/"
    "https://airchains-testnet-rpc.crouton.digital/"
)
rollback_retries=0
max_rollback_retries=1
rpc_index=0
rpc_switch_threshold=2
error_count=0

# Function to switch RPC endpoint in a round-robin fashion
switch_rpc_endpoint() {
    rpc_index=$(( (rpc_index + 1) % ${#rpc_endpoints[@]} ))
    local new_rpc_endpoint=${rpc_endpoints[$rpc_index]}
    echo "Switching to new RPC endpoint: $new_rpc_endpoint at $(date)" | tee -a "$log_file"
    sed -i 's|JunctionRPC = ".*"|JunctionRPC = "'"$new_rpc_endpoint"'"|' $HOME/.tracks/config/sequencer.toml
    sudo systemctl restart stationd
    echo "Restarted stationd with new RPC endpoint $new_rpc_endpoint at $(date)" | tee -a "$log_file"
    sleep 60
}

# Function to handle pod creation timeout
handle_pod_creation_timeout() {
    rollback_retries=$((rollback_retries + 1))
    if [[ $rollback_retries -gt $max_rollback_retries ]]; then
        echo "Rollback attempts exceeded limit. Switching RPC." | tee -a "$log_file"
        rollback_retries=0
        switch_rpc_endpoint
    else
        echo "No new pod created in the last 5 minutes at $(date). Running rollback steps." | tee -a "$log_file"
        {
            sudo systemctl stop stationd
            cd /root/tracks
            git pull
            /usr/local/go/bin/go run cmd/main.go rollback
            /usr/local/go/bin/go run cmd/main.go rollback
            /usr/local/go/bin/go run cmd/main.go rollback
            sudo systemctl restart stationd
            systemctl daemon-reload
            systemctl restart stationd
            echo "Completed at $(date)"
        } >> /root/restart_stationd.log 2>&1
    fi
}

# Function to handle repeated errors
handle_repeated_errors() {
    error_count=$((error_count + 1))
    if [[ $error_count -ge $rpc_switch_threshold ]]; then
        echo "Error repeated $rpc_switch_threshold times. Switching RPC." | tee -a "$log_file"
        switch_rpc_endpoint
        error_count=0
    fi
}

# Function to check logs for errors
check_logs_for_errors() {
    local logs="$1"
    for pattern in "${error_patterns[@]}"; do
        if grep -q "$pattern" <<< "$logs"; then
            return 0
        fi
    done
    return 1
}

# Function to check logs for critical errors
check_logs_for_critical_errors() {
    local logs="$1"
    for pattern in "${critical_error_patterns[@]}"; do
        if grep -q "$pattern" <<< "$logs"; then
            return 0
        fi
    done
    return 1
}

# Function to check logs for RPC errors
check_logs_for_rpc_errors() {
    local logs="$1"
    for pattern in "${rpc_error_patterns[@]}"; do
        if grep -q "$pattern" <<< "$logs"; then
            return 0
        fi
    done
    return 1
}

# Function to check logs for additional errors
check_logs_for_additional_errors() {
    local logs="$1"
    for pattern in "${additional_error_patterns[@]}"; do
        if grep -q "$pattern" <<< "$logs"; then
            return 0
        fi
    done
    return 1
}

# Function to check logs for persistent errors
check_logs_for_persistent_errors() {
    local logs="$1"
    for pattern in "${persistent_error_patterns[@]}"; do
        if grep -q "$pattern" <<< "$logs"; then
            return 0
        fi
    done
    return 1
}

# Monitor logs continuously
monitor_logs() {
    sudo journalctl -u "$service_name" -f --no-hostname -o cat | while read -r line; do
        echo "$line" | tee -a "$log_file"
        if check_logs_for_errors "$line"; then
            if check_logs_for_critical_errors "$line"; then
                echo "Critical error detected at $(date). Running rollback steps immediately." | tee -a "$log_file"
                handle_repeated_errors
            elif check_logs_for_rpc_errors "$line"; then
                echo "RPC error detected at $(date). Switching RPC endpoint." | tee -a "$log_file"
                handle_repeated_errors
            elif check_logs_for_additional_errors "$line"; then
                echo "Additional error detected at $(date). Switching RPC endpoint." | tee -a "$log_file"
                handle_repeated_errors
            elif check_logs_for_persistent_errors "$line"; then
                echo "Persistent error detected at $(date). Restarting $service_name." | tee -a "$log_file"
                handle_repeated_errors
            else
                echo "Error detected at $(date): $line" | tee -a "$log_file"
            fi
        fi
    done
}

echo "Starting log monitoring for $service_name..." | tee -a "$log_file"
monitor_logs
