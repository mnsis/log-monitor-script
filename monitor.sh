#!/bin/bash

# Define variables
service_name="stationd"
error_patterns=(
    "account sequence mismatch"
    "Failed to get transaction by hash"
    "request ratelimited"
    "\[GIN\] .* \| 404 \|"
    "Failed to Init VRF"
    "incorrect pod number"
    "error unmarshalling: invalid character '<' looking for beginning of value"
    "VRF record is nil"
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
)
rpc_endpoints=(
    "https://t-airchains.rpc.utsa.tech/"
    "https://airchains-rpc.sbgid.com/"
    "https://testnet.rpc.airchains.silentvalidator.com/"
    "https://airchains-testnet-rpc.crouton.digital/"
    "https://airchains-testnet-rpc.itrocket.net/"
)
check_interval=30  # Interval to check logs in seconds
error_duration=$((5 * 60))  # Duration to wait before verifying if error persists in seconds (5 minutes)
log_file="/tmp/stationd_monitor.log"
last_errors_file="/tmp/stationd_last_errors"
max_retries=3
rollback_retries=0
max_rollback_retries=1  # Number of rollback attempts before switching RPC
last_pod_time_file="/tmp/last_pod_time"
last_pod_number_file="/tmp/last_pod_number"
last_rollback_pod_file="/tmp/last_rollback_pod"
rpc_index=0
rpc_switch_threshold=2  # Number of consecutive failures before switching RPC
error_count_file="/tmp/error_count_file"

# Telegram variables
# TOKEN="your-telegram-token"
# CHAT_ID="your-chat-id"

echo "Starting log monitoring for $service_name..." | tee -a "$log_file"

# Function to check logs for errors
check_logs_for_errors() {
    local logs="$1"
    local errors=()
    for pattern in "${error_patterns[@]}"; do
        if [[ "$logs" =~ $pattern ]]; then
            errors+=("$pattern")
        fi
    done
    echo "${errors[@]}"
}

# Function to check logs for critical errors
check_logs_for_critical_errors() {
    local logs="$1"
    for pattern in "${critical_error_patterns[@]}"; do
        if [[ "$logs" =~ $pattern ]]; then
            return 0  # Critical error detected
        fi
    done
    return 1  # No critical error detected
}

# Function to check logs for RPC errors
check_logs_for_rpc_errors() {
    local logs="$1"
    for pattern in "${rpc_error_patterns[@]}"; do
        if [[ "$logs" =~ $pattern ]]; then
            return 0  # RPC error detected
        fi
    done
    return 1  # No RPC error detected
}

# Function to check logs for additional errors
check_logs_for_additional_errors() {
    local logs="$1"
    for pattern in "${additional_error_patterns[@]}"; do
        if [[ "$logs" =~ $pattern ]]; then
            return 0  # Additional error detected
        fi
    done
    return 1  # No additional error detected
}

# Function to check logs for persistent errors
check_logs_for_persistent_errors() {
    local logs="$1"
    for pattern in "${persistent_error_patterns[@]}"; do
        if [[ "$logs" =~ $pattern ]]; then
            return 0  # Persistent error detected
        fi
    done
    return 1  # No persistent error detected
}

# Function to switch RPC endpoint in a round-robin fashion
switch_rpc_endpoint() {
    rpc_index=$(( (rpc_index + 1) % ${#rpc_endpoints[@]} ))
    local new_rpc_endpoint=${rpc_endpoints[$rpc_index]}
    echo "Switching to new RPC endpoint: $new_rpc_endpoint at $(date)" | tee -a "$log_file"
    # send_telegram_message "Switching to new RPC endpoint: $new_rpc_endpoint at $(date)"
    sed -i 's|JunctionRPC = ".*"|JunctionRPC = "'"$new_rpc_endpoint"'"|' $HOME/.tracks/config/sequencer.toml
    sudo systemctl restart stationd
    echo "Restarted stationd with new RPC endpoint $new_rpc_endpoint at $(date)" | tee -a "$log_file"
    # send_telegram_message "Restarted stationd with new RPC endpoint $new_rpc_endpoint at $(date)"
    sleep 60  # Add a delay to avoid rapid restarts

    # Check immediately if the new RPC endpoint is not reachable
    logs=$(journalctl -u "$service_name" -n 50 --no-pager)
    if check_logs_for_additional_errors "$logs"; then
        echo "Detected connection error with new RPC endpoint: $new_rpc_endpoint. Switching to next RPC." | tee -a "$log_file"
        switch_rpc_endpoint
    fi
}

# Function to handle pod creation timeout
handle_pod_creation_timeout() {
    rollback_retries=$((rollback_retries + 1))
    if [[ $rollback_retries -gt $max_rollback_retries ]]; then
        echo "Rollback attempts exceeded limit. Switching RPC." | tee -a "$log_file"
        switch_rpc_endpoint
        rollback_retries=0
    else
        echo "No new pod created in the last 5 minutes at $(date). Running rollback steps." | tee -a "$log_file"
        # send_telegram_message "No new pod created in the last 5 minutes at $(date). Running rollback steps."
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
            echo "$latest_pod_number" > "$last_rollback_pod_file"
            echo "Completed at $(date)"
        } >> /root/restart_stationd.log 2>&1

        # Check immediately if the new RPC endpoint is not reachable
        logs=$(journalctl -u "$service_name" -n 50 --no-pager)
        if check_logs_for_additional_errors "$logs"; then
            echo "Detected connection error with RPC endpoint after rollback. Switching to next RPC." | tee -a "$log_file"
            switch_rpc_endpoint
        fi
    fi
}

# Function to restart service with a delay
restart_service_with_delay() {
    systemctl daemon-reload
    systemctl restart "$service_name"
    if systemctl is-active --quiet "$service_name"; then
        echo "Service $service_name restarted successfully at $(date)." | tee -a "$log_file"
    else
        echo "Service $service_name failed to restart at $(date)." | tee -a "$log_file"
    fi
    sleep 10  # Add a delay to avoid rapid restarts
}

# Monitor for pod creation and handle rollback if needed
monitor_pod_creation() {
    # Get the last 50 lines of service logs
    logs=$(journalctl -u "$service_name" -n 50 --no-pager)
    
    # Check for pod processing logs and extract the latest pod number
    latest_pod_number=$(echo "$logs" | grep -oP 'Processing Pod Number: \K[0-9]+' | tail -n 1)
    current_time=$(date +%s)
    
    if [ -n "$latest_pod_number" ]; then
        echo "Latest pod number: $latest_pod_number at $(date)" | tee -a "$log_file"
        echo "$latest_pod_number" > "$last_pod_number_file"
        echo "$current_time" > "$last_pod_time_file"
    else
        echo "No pod number found in logs at $(date)" | tee -a "$log_file"
    fi

    # Wait for error duration before rechecking
    sleep "$error_duration"

    # Recheck logs after waiting
    logs=$(journalctl -u "$service_name" -n 50 --no-pager)
    current_pod_number=$(echo "$logs" | grep -oP 'Processing Pod Number: \K[0-9]+' | tail -n 1)
    current_time=$(date +%s)

    if [ -n "$current_pod_number" ]; then
        echo "Rechecked pod number: $current_pod_number at $(date)" | tee -a "$log_file"
        if [[ "$current_pod_number" == "$latest_pod_number" && "$current_pod_number" != "$(cat $last_rollback_pod_file 2>/dev/null)" ]]; then
            echo "Pod number did not change and no rollback occurred from this pod. Running rollback." | tee -a "$log_file"
            handle_pod_creation_timeout
        else
            echo "Pod number changed or rollback already done from this pod. Updating last pod number and time." | tee -a "$log_file"
            echo "$current_pod_number" > "$last_pod_number_file"
            echo "$current_time" > "$last_pod_time_file"
            echo 0 > "$error_count_file"
        fi
    else
        echo "No pod number found in recheck. Running rollback." | tee -a "$log_file"
        handle_pod_creation_timeout
    fi
}

# Function to handle repeated errors
handle_repeated_errors() {
    error_count=$(cat "$error_count_file" 2>/dev/null)
    error_count=$((error_count + 1))
    echo "$error_count" > "$error_count_file"
    
    if [[ $error_count -ge $rpc_switch_threshold ]]; then
        echo "Error repeated $rpc_switch_threshold times. Switching RPC." | tee -a "$log_file"
        switch_rpc_endpoint
        echo 0 > "$error_count_file"
    else
        echo "Error count: $error_count" | tee -a "$log_file"
    fi
}

# Monitor for errors and handle restart if needed
monitor_errors() {
    # Get the last 10 lines of service logs
    logs=$(journalctl -u "$service_name" -n 10 --no-pager)

    # Check for critical errors
    if check_logs_for_critical_errors "$logs"; then
        echo "Critical error detected at $(date). Running rollback steps immediately." | tee -a "$log_file"
        handle_repeated_errors
        return  # Skip the rest of the loop
    fi
    
    # Check for RPC errors
    if check_logs_for_rpc_errors "$logs"; then
        echo "RPC error detected at $(date). Switching RPC endpoint." | tee -a "$log_file"
        handle_repeated_errors
        return  # Skip the rest of the loop and continue with the new RPC endpoint
    fi

    # Check for additional errors
    if check_logs_for_additional_errors "$logs"; then
        echo "Additional error detected at $(date). Switching RPC endpoint." | tee -a "$log_file"
        handle_repeated_errors
        return  # Skip the rest of the loop and continue with the new RPC endpoint
    fi

    # Check for persistent errors
    if check_logs_for_persistent_errors "$logs"; then
        echo "Persistent error detected at $(date). Restarting $service_name." | tee -a "$log_file"
        handle_repeated_errors
        return  # Skip the rest of the loop
    fi
    
    current_errors=$(check_logs_for_errors "$logs")
    if [ -n "$current_errors" ]; then
        # Read last errors
        last_errors=$(cat "$last_errors_file" 2>/dev/null)
        
        # Check if current errors are new
        new_errors=()
        for error in $current_errors; do
            if [[ ! "$last_errors" =~ $error ]]; then
                new_errors+=("$error")
            fi
        done
        
        if [ -n "$new_errors" ]; then
            echo "${new_errors[@]}" > "$last_errors_file"
            echo "New error patterns '${new_errors[@]}' detected at $(date). Waiting for $error_duration seconds to recheck." | tee -a "$log_file"
            sleep "$error_duration"
            
            # Recheck logs after waiting
            logs=$(journalctl -u "$service_name" -n 10 --no-pager)
            current_errors=$(check_logs_for_errors "$logs")
            persistent_errors=()
            for error in $current_errors; do
                if [[ " ${new_errors[@]} " =~ " ${error} " ]]; then
                    persistent_errors+=("$error")
                fi
            done
            
            if [ -n "$persistent_errors" ]; then
                echo "Error patterns '${persistent_errors[@]}' still present at $(date). Restarting $service_name." | tee -a "$log_file"
                handle_repeated_errors
            else
                echo "Error patterns '${new_errors[@]}' cleared by itself, no restart needed at $(date)." | tee -a "$log_file"
                echo "" > "$last_errors_file"
                echo 0 > "$error_count_file"
            fi
        fi
    fi
}

while true; do
    monitor_pod_creation
    monitor_errors
    sleep "$check_interval"
done
