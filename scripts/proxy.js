#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js"
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js"
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
  ListPromptsRequestSchema,
  GetPromptRequestSchema
} from "@modelcontextprotocol/sdk/types.js"
import { attach } from "neovim"
import { createServer } from "net"
import { promises as fs } from "fs"
import { parseArgs } from "util"

process.on("uncaughtException", (error) => {
  console.error("Uncaught exception:", error)
  process.exit(1)
})

process.on("unhandledRejection", (reason, promise) => {
  console.error("Unhandled rejection at:", promise, "reason:", reason)
  process.exit(1)
})

// Parse command line arguments using Node.js native parser
const { values, positionals } = parseArgs({
  options: {
    "rpc-call-timeout": {
      type: "string",
      short: "t"
    }
  },
  allowPositionals: true
})

// Get proxy socket from positional arguments
const SOCKET = positionals[0]

// Get RPC call timeout from options or use default
const RPC_CALL_TIMEOUT = values["rpc-call-timeout"] ? parseInt(values["rpc-call-timeout"], 10) : 60000

// Timeout configurations
const CONNECTION_TIMEOUT = 5000 // 5 seconds to connect to Neovim

// Get Neovim socket from environment (NVIM is set automatically by Neovim)
const NVIM = process.env.NVIM

if (!NVIM) {
  console.error("Error: NVIM environment variable is required")
  console.error("Usage: NVIM=/path/to/nvim.sock node proxy.js /path/to/proxy.sock [--rpc-call-timeout <ms>]")
  process.exit(1)
}

if (!SOCKET) {
  console.error("Error: Proxy socket path argument is required")
  console.error("Usage: NVIM=/path/to/nvim.sock node proxy.js /path/to/proxy.sock [--rpc-call-timeout <ms>]")
  process.exit(1)
}

console.error("RPC call timeout:", RPC_CALL_TIMEOUT, "ms")

// Global Neovim connection - reused across requests
let nvim = null
let allServers = [] // All MCP servers (native + HTTP) from hub
let isConnecting = false

/**
 * Wrap an RPC call with a timeout
 * @param {Promise} promise - The RPC call promise
 * @param {string} operation - Description of the operation for error messages
 * @returns {Promise} - Promise that rejects if timeout is reached
 */
function withTimeout(promise, operation) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(`RPC call timeout after ${RPC_CALL_TIMEOUT}ms for operation: ${operation}`)), RPC_CALL_TIMEOUT))
  ])
}

/**
 * Connect to Neovim RPC socket
 * Neovim is guaranteed to be running since it spawned this proxy
 */
async function connect() {
  if (nvim) {
    return // Already connected
  }

  if (isConnecting) {
    // Wait for existing connection attempt
    while (isConnecting) {
      await new Promise((resolve) => setTimeout(resolve, 100))
    }
    return
  }

  isConnecting = true

  console.error("Attaching to Neovim RPC socket: ", NVIM)

  // Add timeout to the attach call
  nvim = await Promise.race([attach({ socket: NVIM }), new Promise((_, reject) => setTimeout(() => reject(new Error("Connection timeout")), CONNECTION_TIMEOUT))])

  console.error(`Connected to Neovim at ${NVIM}`)

  isConnecting = false
}

/**
 * Fetch all servers from Neovim hub
 */
async function refresh() {
  if (!nvim) {
    throw new Error("Not connected to Neovim")
  }

  try {
    allServers = await nvim.lua('return require("mcphub.native.neovim.rpc").get_all_servers()')
    console.error(`Loaded ${allServers.length} MCP server(s): ${allServers.map((s) => s.name).join(", ")}`)
  } catch (error) {
    console.error("Failed to fetch servers from hub:", error.message)
    throw error
  }
}

/**
 * Create and configure the MCP server
 */
/**
 * Create and configure the MCP server
 */
function start() {
  const server = new Server(
    {
      name: "proxy",
      version: "1.0.0"
    },
    {
      capabilities: {
        tools: {},
        resources: {},
        prompts: {}
      }
    }
  )

  // Handle tools/list
  server.setRequestHandler(ListToolsRequestSchema, async () => {
    // Connect if not already connected
    await connect()
    // Always refresh servers to get latest state from Neovim
    await refresh()

    const all = []
    for (const mcpServer of allServers) {
      for (const tool of mcpServer.capabilities.tools || []) {
        all.push({
          name: `${mcpServer.name}__${tool.name}`,
          description: tool.description || `${tool.name} from ${mcpServer.name}`,
          inputSchema: tool.inputSchema || { type: "object", properties: {} }
        })
      }
    }

    return { tools: all }
  })

  // Handle tools/call
  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    // Connect if not already connected
    await connect()

    const { name, arguments: args } = request.params

    // Parse server and tool name (format: servername__toolname)
    const [serverName, ...toolParts] = name.split("__")
    const toolName = toolParts.join("__")

    try {
      const result = await withTimeout(
        nvim.lua(
          `
          return require("mcphub.native.neovim.rpc").hub_call_tool(...)
        `,
          [serverName, toolName, { arguments: args || {}, caller: { type: "external", source: "rpc-proxy" } }]
        ),
        `call_tool(${serverName}/${toolName})`
      )

      if (result.error) {
        throw new Error(result.error)
      }

      return {
        content: result.content || []
      }
    } catch (error) {
      throw new Error(`Error calling tool: ${error.message}`)
    }
  })

  // Handle resources/list
  server.setRequestHandler(ListResourcesRequestSchema, async () => {
    // Connect if not already connected
    await connect()
    // Always refresh servers to get latest state from Neovim
    await refresh()

    const all = []
    for (const mcpServer of allServers) {
      for (const resource of mcpServer.capabilities.resources || []) {
        all.push({
          uri: `${mcpServer.name}://${resource.uri}`,
          name: resource.name || resource.uri,
          description: resource.description,
          mimeType: resource.mimeType
        })
      }
    }

    return { resources: all }
  })

  // Handle resources/read
  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    // Connect if not already connected
    await connect()

    const { uri } = request.params

    // Parse server name from URI (format: servername://path)
    const match = uri.match(/^([^:]+):\/\/(.+)$/)
    if (!match) {
      throw new Error(`Invalid resource URI: ${uri}`)
    }

    const [, serverName, resourceUri] = match

    try {
      const result = await withTimeout(
        nvim.lua(
          `
          return require("mcphub.native.neovim.rpc").hub_access_resource(...)
        `,
          [serverName, resourceUri, { caller: { type: "external", source: "rpc-proxy" } }]
        ),
        `access_resource(${serverName}/${resourceUri})`
      )

      if (result.error) {
        throw new Error(result.error)
      }

      return {
        contents: result.contents || []
      }
    } catch (error) {
      throw new Error(`Error reading resource: ${error.message}`)
    }
  })

  // Handle prompts/list
  server.setRequestHandler(ListPromptsRequestSchema, async () => {
    // Connect if not already connected
    await connect()
    // Always refresh servers to get latest state from Neovim
    await refresh()

    const allPrompts = []
    for (const mcpServer of allServers) {
      for (const prompt of mcpServer.capabilities.prompts || []) {
        allPrompts.push({
          name: `${mcpServer.name}__${prompt.name}`,
          description: prompt.description,
          arguments: prompt.arguments || []
        })
      }
    }

    return { prompts: allPrompts }
  })

  // Handle prompts/get
  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    // Connect if not already connected
    await connect()

    const { name, arguments: args } = request.params

    // Parse server and prompt name (format: servername__promptname)
    const [serverName, ...promptParts] = name.split("__")
    const promptName = promptParts.join("__")

    try {
      const result = await withTimeout(
        nvim.lua(
          `
          return require("mcphub.native.neovim.rpc").hub_get_prompt(...)
        `,
          [serverName, promptName, { arguments: args || {}, caller: { type: "external", source: "rpc-proxy" } }]
        ),
        `get_prompt(${serverName}/${promptName})`
      )

      if (result.error) {
        throw new Error(result.error)
      }

      return {
        messages: result.messages || [],
        description: result.description
      }
    } catch (error) {
      throw new Error(`Error getting prompt: ${error.message}`)
    }
  })

  return server
}

// Removed custom SocketTransport class - using StdioServerTransport from SDK instead

/**
 * Main entry point
 */
async function main() {
  console.error("Main function started")
  console.error("NVIM socket:", NVIM)
  console.error("Proxy socket:", SOCKET)

  // Remove old socket file if it exists
  try {
    await fs.unlink(SOCKET)
    console.error("Removed existing socket file")
  } catch (err) {
    // Ignore if file doesn't exist
  }

  // Create Unix socket server
  const socketServer = createServer((socket) => {
    console.error("Client connected to proxy socket")

    // Create a new MCP server instance for each client
    const mcpServer = start()

    // Use StdioServerTransport from SDK with the socket as stdin/stdout
    const transport = new StdioServerTransport(socket, socket)

    // Handle socket events
    socket.on("error", (err) => {
      console.error("Socket error:", err)
    })

    socket.on("close", () => {
      console.error("Client disconnected from proxy socket")
    })

    // Connect MCP server to this transport
    mcpServer.connect(transport).catch((err) => {
      console.error("Failed to connect MCP server to transport:", err)
      socket.destroy()
    })
  })

  // Start listening on Unix socket first
  socketServer.listen(SOCKET, () => {
    console.error(`Neovim RPC Proxy server listening on Unix socket: ${SOCKET}`)
    console.error("Proxy is ready - will connect to Neovim on first request")
  })

  socketServer.on("error", (err) => {
    console.error("Socket server error:", err)
    process.exit(1)
  })
}

// Handle cleanup - properly close the RPC connection without quitting Neovim
process.on("SIGINT", () => {
  console.error("\nShutting down (SIGINT)...")
  cleanup()
  process.exit(0)
})

process.on("SIGTERM", () => {
  console.error("\nShutting down (SIGTERM)...")
  cleanup()
  process.exit(0)
})

// Handle Neovim disconnection
process.on("exit", () => {
  cleanup()
})

// Cleanup function to properly close RPC connection
function cleanup() {
  if (nvim) {
    try {
      // Close the transport/socket connection, don't quit Neovim itself
      // The neovim client doesn't expose a proper close method, so we clear the reference
      // The socket will be closed when the process exits
      nvim = null
      allServers = []
      console.error("Cleaned up Neovim RPC connection")
    } catch (e) {
      console.error("Error during cleanup:", e.message)
    }
  }
  
  // Clean up socket file if it exists
  try {
    if (SOCKET) {
      require('fs').unlinkSync(SOCKET)
      console.error("Removed socket file:", SOCKET)
    }
  } catch (e) {
    // Socket file might not exist or already removed
  }
}

// Start the server
main().catch((error) => {
  console.error("Fatal error:", error)
  process.exit(1)
})
