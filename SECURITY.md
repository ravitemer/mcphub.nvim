# Security Policy

## Supported Versions

Use this section to tell people about which versions of MCPHub.nvim are currently being supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0.0 | :x:                |

## Security Considerations

### MCP Hub Integration

1. **Port Security**

   - The plugin communicates with MCP Hub on a local port
   - Default port (37373) can be configured
   - Creates Express server at `http://localhost:[config.port]` or at `config.server_url`
   - Ensure firewall rules don't expose the port externally

2. **Configuration Security**

   - Configuration files may contain sensitive data
   - Store config files with appropriate permissions
   - Don't commit configuration with secrets
   - Use environment variables for sensitive data

3. **Plugin Permissions**
   - Plugin runs with Neovim's permissions
   - Be cautious with file operations
   - Validate all paths before operations
   - Don't execute arbitrary commands

## Reporting a Vulnerability

We take the security of MCPHub.nvim seriously. If you believe you have found a security vulnerability, please report it to us as described below.

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to [mail](). You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

Please include the following information:

- Type of issue
- Location of the affected source code
- Step-by-step instructions to reproduce
- Impact of the issue
- Suggested fix if possible

## Preferred Languages

We prefer all communications to be in English.

## Disclosure Policy

When we receive a security bug report, we will:

1. Confirm the problem and determine affected versions
2. Audit code for similar problems
3. Prepare fixes for all supported versions
4. Release new security versions
5. Announce the vulnerability and fixes

## Comments on this Policy

If you have suggestions on how this process could be improved, please submit a pull request.
