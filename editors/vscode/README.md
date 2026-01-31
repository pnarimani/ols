# Odin Language Server

Language server that gives go to definition, completion, signature help, syntax highlighting, and many other useful features.


![Example](images/completion.png)

## TCP Mode (for debugging)

For OLS development, you can connect the extension to an existing OLS instance running with a debugger attached:

1. Start OLS in TCP mode:
   ```
   ols --tcp --port=6969
   ```

2. Configure VS Code settings:
   ```json
   {
     "ols.server.connectionMode": "tcp",
     "ols.server.tcpPort": 6969
   }
   ```

3. Reload the VS Code window - the extension will connect to your running OLS instance.

The extension will retry connecting for up to 60 seconds, so you can start OLS after reloading VS Code.

