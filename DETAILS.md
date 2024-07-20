### Script Functionality Explanation

The script monitors a specific service (`stationd`) and performs various actions based on the errors detected in the logs. Here is a detailed explanation of each part:

1. **Variable Definitions:**
    - `service_name`: The name of the service to be monitored.
    - `error_patterns`, `critical_error_patterns`, `rpc_error_patterns`, `additional_error_patterns`, `persistent_error_patterns`: Patterns of errors to look for in the logs.
    - `rpc_endpoints`: A list of RPC endpoints to switch between in case errors are detected.
    - `check_interval`: The interval between log checks.
    - `error_duration`: The duration to wait before rechecking logs after an error is detected.
    - `log_file`: The log file for the script.
    - `last_errors_file`, `last_pod_time_file`, `last_pod_number_file`, `last_rollback_pod_file`, `error_count_file`: Files to store information related to errors and pods.
    - `max_retries`, `rollback_retries`, `max_rollback_retries`: Variables to control the number of rollback attempts and RPC switching.

2. **`check_logs_for_errors` Function:**
    Searches for specified error patterns in the logs and returns a list of detected errors.

3. **`check_logs_for_critical_errors` Function:**
    Searches for critical errors in the logs and returns 0 if a critical error is found, and 1 if no critical error is found.

4. **`check_logs_for_rpc_errors` Function:**
    Searches for RPC errors in the logs and returns 0 if an RPC error is found, and 1 if no RPC error is found.

5. **`check_logs_for_additional_errors` Function:**
    Searches for additional errors in the logs and returns 0 if an additional error is found, and 1 if no additional error is found.

6. **`check_logs_for_persistent_errors` Function:**
    Searches for persistent errors in the logs and returns 0 if a persistent error is found, and 1 if no persistent error is found.

7. **`switch_rpc_endpoint` Function:**
    Switches the RPC endpoint to a new one from the list and restarts the service.

8. **`handle_pod_creation_timeout` Function:**
    Handles the situation where no new pod is created within a specified time. If the number of rollback attempts exceeds the limit, it switches to a new RPC endpoint.

9. **`restart_service_with_delay` Function:**
    Restarts the service with a delay to avoid rapid restarts.

10. **`monitor_pod_creation` Function:**
    Monitors pod creation and handles the situation where the pod number does not change within a specified time.

11. **`handle_repeated_errors` Function:**
    Handles repeated errors. If the error repeats a specified number of times, it switches to a new RPC endpoint.

12. **`monitor_errors` Function:**
    Monitors errors in the logs and handles them based on the type of error detected.

13. **Main Loop:**
    Runs the pod creation and error monitoring functions continuously at the specified interval.

### Enabling Telegram Notifications

To enable Telegram notifications, you need to add a function to send messages via Telegram and then use this function to send notifications when certain events occur.

1. **Create a Telegram Bot:**
    - Open the Telegram app and search for the `BotFather`.
    - Follow the instructions to create a new bot and get the bot token.

2. **Get Your Chat ID:**
    - Search for the `@userinfobot` in Telegram and send it a message `/start`.
    - You will receive information including your `Chat ID`.

3. **Add a Function to Send Messages to Telegram:**
    Add the following function to the script:

    ```bash
    # Function to send message to Telegram
    send_telegram_message() {
        local message="$1"
        local token="your-telegram-token"
        local chat_id="your-chat-id"
        curl -s -X POST "https://api.telegram.org/bot$token/sendMessage" \
            -d chat_id="$chat_id" \
            -d text="$message"
    }
    ```

    Replace `your-telegram-token` with your bot token and `your-chat-id` with your Chat ID.

4. **Use the Send Message Function:**
    Use the `send_telegram_message` function to send notifications when certain events occur, such as switching to a new RPC endpoint or detecting a critical error. For example:

    ```bash
    # Function to switch RPC endpoint in a round-robin fashion
    switch_rpc_endpoint() {
        rpc_index=$(( (rpc_index + 1) % ${#rpc_endpoints[@]} ))
        local new_rpc_endpoint=${rpc_endpoints[$rpc_index]}
        echo "Switching to new RPC endpoint: $new_rpc_endpoint at $(date)" | tee -a "$log_file"
        send_telegram_message "Switching to new RPC endpoint: $new_rpc_endpoint at $(date)"
        sed -i 's|JunctionRPC = ".*"|JunctionRPC = "'"$new_rpc_endpoint"'"|' $HOME/.tracks/config/sequencer.toml
        sudo systemctl restart stationd
        echo "Restarted stationd with new RPC endpoint $new_rpc_endpoint at $(date)" | tee -a "$log_file"
        send_telegram_message "Restarted stationd with new RPC endpoint $new_rpc_endpoint at $(date)"
        sleep 60  # Add a delay to avoid rapid restarts

        # Check immediately if the new RPC endpoint is not reachable
        logs=$(journalctl -u "$service_name" -n 50 --no-pager)
        if check_logs_for_additional_errors "$logs"; then
            echo "Detected connection error with new RPC endpoint: $new_rpc_endpoint. Switching to next RPC." | tee -a "$log_file"
            send_telegram_message "Detected connection error with new RPC endpoint: $new_rpc_endpoint. Switching to next RPC."
            switch_rpc_endpoint
        fi
    }
    ```

By following these steps, you can monitor the service and receive instant notifications via Telegram when any issues or changes occur.
