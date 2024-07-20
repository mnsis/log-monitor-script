# log-monitor-script
Script to monitor logs and handle errors for the stationd service.

```markdown
# Log Monitoring Script

This script monitors logs and handles errors for the `stationd` service.

## How to Use

### Step 1: Download the Script

Open your terminal and run the following command to download the script:

```bash
wget https://github.com/mnsis/log-monitor-script/blob/main/monitor.sh -O monitor.sh
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

5. Save the changes and run the script as described above.

By following these steps, you can effectively use the log monitoring script, run it in the background, and receive notifications via Telegram.
