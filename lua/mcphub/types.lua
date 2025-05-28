---@meta

---@class MarketplaceItem
---@field mcpId string
---@field name string
---@field author string
---@field description string
---@field codiconIcon string
---@field logoUrl string
---@field category string
---@field tags string[]
---@field requiresApiKey boolean
---@field isRecommended boolean
---@field githubStars integer
---@field githubUrl string
---@field downloadCount integer
---@field createdAt string
---@field updatedAt string

---@class CustomMCPServerConfig.CustomInstructions
---@field text string
---@field disabled? string

---@class CustomMCPServerConfig
---@field disabled? boolean
---@field disabled_tools? string[]
---@field disabled_prompts? string[]
---@field disabled_resources? string[]
---@field disabled_resourceTemplates? string[]
---@field custom_instructions? CustomMCPServerConfig.CustomInstructions
---@field autoApprove? boolean|string[] -- true for all tools, array of tool names for specific tools

---@class MCPServerConfig: CustomMCPServerConfig
---@field command? string
---@field args? table
---@field env? table<string,string>
---@field headers? table<string,string>
---@field url? string

---@class NativeMCPServerConfig : CustomMCPServerConfig

---@class MCPServer
---@field name string
---@field displayName string
---@field description string
---@field transportType string
---@field status MCPHub.Constants.ConnectionStatus
---@field error string
---@field capabilities MCPCapabilities
---@field uptime number
---@field lastStarted string
---@field authorizationUrl string

---@class LogEntry
---@field type string
---@field message string
---@field timestamp number
---@field data table<string,any>
---@field code number

---@class MCPResponseOutput
---@field text string
---@field images table[]
---@field blobs table[]
---@field audios table[]
---@field error? string

---@class EnhancedMCPPrompt : MCPPrompt
---@field server_name string

---@class EnhancedMCPResourceTemplate : MCPResourceTemplate
---@field server_name string

---@class EnhancedMCPResource : MCPResource
---@field server_name string

---@class EnhancedMCPTool : MCPTool
---@field server_name string

---@class MCPRequestOptions
---@field timeout? number
---@field resetTimeoutOnProgress? boolean
---@field maxTotalTimeout? number
