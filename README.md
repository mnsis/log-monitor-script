# log-monitor-script
Script to monitor logs and handle errors for the stationd service.

### Step 1: Download the Script

Clone the repository and navigate into the directory:

```bash
git clone https://github.com/mnsis/log-monitor-script.git
cd log-monitor-script
chmod +x monitor.sh
```

### Step 2: Run the Script

To start the script, simply run:

```bash
./monitor.sh
```

### Running the Script in the Background using `screen`

To keep the script running in the background, you can use `screen`. Follow these steps:

1. Install `screen` if it's not already installed:

   ```bash
   sudo apt-get install screen
   ```

2. Start a new `screen` session:

   ```bash
   screen -S log-monitor
   ```

3. Run the script within the `screen` session:

   ```bash
   ./monitor.sh
   ```

4. Detach from the `screen` session to keep it running in the background:

   Press `Ctrl + A`, then `D`.

5. To reattach to the `screen` session later, use:

   ```bash
   screen -r log-monitor
   ```

### Enabling Telegram Notifications

The script has the capability to send notifications to a Telegram bot. To enable this feature:

1. Create a Telegram bot and get the API token. You can do this by talking to the [BotFather](https://telegram.me/BotFather).

2. Get your chat ID. You can do this by talking to the [GetID Bot](https://telegram.me/userinfobot).

3. Edit the script to add your Telegram token and chat ID:

   ```bash
   nano monitor.sh
   ```

4. Uncomment and replace the placeholder values with your actual `TOKEN` and `CHAT_ID`:

   ```bash
   # Telegram variables
   TOKEN="your-telegram-token"
   CHAT_ID="your-chat-id"
   ```

   Remove the `#` at the beginning of these lines to uncomment them.

5. Save the changes and run the script as described above.

### Cleaning Up Temporary Files

To ensure that temporary files created by the script are regularly cleaned up, you can use the following script and set it up as a cron job:

1. Create a cleanup script:

   ```bash
   nano /root/clean_tmp.sh
   ```

   Add the following content to the file:

   ```bash
   #!/bin/bash
   {
       echo "Cleaning /tmp at $(date)"
       # Find all files older than two hours and delete them
       find /tmp -type f -mmin +120 -exec rm -f {} \;
       echo "Completed at $(date)"
   } >> /root/clean_tmp.log 2>&1
   ```

2. Make the script executable:

   ```bash
   chmod +x /root/clean_tmp.sh
   ```

3. Set up a cron job to run the script every two hours:

   ```bash
   crontab -e
   ```

   Add the following line to the crontab file:

   ```bash
   0 */2 * * * /root/clean_tmp.sh
   ```

4. Run the cleanup script manually to verify it works:

   ```bash
   sudo /root/clean_tmp.sh
   ```

5. Check the log to ensure the script ran successfully:

   ```bash
   cat /root/clean_tmp.log
   ```

### Relevant Links

- [GitHub Repository](https://github.com/mnsis/log-monitor-script)
- [Script File](https://github.com/mnsis/log-monitor-script/blob/main/monitor.sh)
