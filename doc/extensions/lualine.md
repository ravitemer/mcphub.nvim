# Lualine Integration

MCP Hub provides multiple ways to integrate with lualine, with the recommended approach using global variables for optimal lazy-loading support.

## Recommended: Global Variables Approach

Use MCPHub's global variables for a lightweight, lazy-load friendly component:

```lua
require('lualine').setup {
    sections = {
        lualine_x = {
            {
                function()
                    -- Check if MCPHub is loaded
                    if not vim.g.loaded_mcphub then
                        return "󰐻 -"
                    end
                    
                    local count = vim.g.mcphub_servers_count or 0
                    local status = vim.g.mcphub_status or "stopped"
                    local executing = vim.g.mcphub_executing
                    
                    -- Show "-" when stopped
                    if status == "stopped" then
                        return "󰐻 -"
                    end
                    
                    -- Show spinner when executing, starting, or restarting
                    if executing or status == "starting" or status == "restarting" then
                        local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
                        local frame = math.floor(vim.loop.now() / 100) % #frames + 1
                        return "󰐻 " .. frames[frame]
                    end
                    
                    return "󰐻 " .. count
                end,
                color = function()
                    if not vim.g.loaded_mcphub then
                        return { fg = "#6c7086" } -- Gray for not loaded
                    end
                    
                    local status = vim.g.mcphub_status or "stopped"
                    if status == "ready" or status == "restarted" then
                        return { fg = "#50fa7b" } -- Green for connected
                    elseif status == "starting" or status == "restarting" then  
                        return { fg = "#ffb86c" } -- Orange for connecting
                    else
                        return { fg = "#ff5555" } -- Red for error/stopped
                    end
                end,
            },
        },
    },
}
```

### Available Global Variables

MCPHub automatically maintains these global variables:
- `vim.g.loaded_mcphub` - Whether MCPHub plugin is loaded (set by plugin loader)
- `vim.g.mcphub_status` - Current hub state ("starting", "ready", "stopped", etc.)
- `vim.g.mcphub_servers_count` - Number of connected servers  
- `vim.g.mcphub_executing` - Whether a tool/resource is currently executing


## Legacy: Full Component (Loads MCPHub) - DEPRECATED

**⚠️ DEPRECATED**: This approach will load MCPHub even with lazy loading enabled and shows a deprecation warning. Use the global variables approach above instead.

```lua
require('lualine').setup {
    sections = {
        lualine_x = {
            {require('mcphub.extensions.lualine')}, -- Uses defaults
        },
    },
}
```

#### When MCP Hub is connecting:

![image](https://github.com/user-attachments/assets/f67802fe-6b0c-48a5-9275-bff9f830ce29)

#### When connected shows number of connected servers:

![image](https://github.com/user-attachments/assets/f90f7cc4-ff34-4481-9732-a0331a26502b)

#### When a tool or resource is being called, shows spinner:

![image](https://github.com/user-attachments/assets/f6bdeeec-48f7-48de-89a5-22236a52843f)

### Legacy Component Options

The lualine component accepts the standard lualine options and the following options:
- `icon`: Icon to display. (default: `"󰐻"`)
- `colored`: Enable dynamic colors (default: `true`)
- `colors`: The color to dynamically display for each MCP Hub state
  - `connecting`: The color to use when MCP Hub is connecting (default: `"DiagnosticWarn"`)
  - `connected`: The color to use when MCP Hub is connected (default: `"DiagnosticInfo"`)
  - `error`: The color to use when MCP Hub encounters an error (default: `"DiagnosticError"`)

#### Customization examples

```lua
-- Custom icon
{require('mcphub.extensions.lualine'), icon = ''}
```

![Image](https://github.com/user-attachments/assets/3f4fd202-d780-441f-a8cf-58d8a8414ab1)

```lua
-- Custom colors
{
  require('mcphub.extensions.lualine'),
  colors = {
    connecting = { fg = "#ffff00" }, -- Yellow
    connected = { fg = "#00ff00" }, -- Green
    error = { fg = "#ff0000" }, -- Red
  },
}
```

![Image](https://github.com/user-attachments/assets/5522b929-d9b1-472c-9bf8-1c14aef36dbe)

```lua
-- Statically color the icon, dynamically color the status text
{require('mcphub.extensions.lualine'), icon = { '󰐻', color = {fg = '#eeeeee'}}}
```

![Image](https://github.com/user-attachments/assets/9f309871-5fda-458f-967e-e7d3d8b269a5)

```lua
-- Dynamically color the icon, statically color the status text
{require('mcphub.extensions.lualine'), color = {fg = '#eeeeee'}}
```

![Image](https://github.com/user-attachments/assets/e3c16813-2210-4b7c-9f79-2737c19c6c30)

```lua
-- Disable coloring
{require('mcphub.extensions.lualine'), colored = false}
```

![Image](https://github.com/user-attachments/assets/78aea188-59e8-4299-a375-1acc0784c7bf)
