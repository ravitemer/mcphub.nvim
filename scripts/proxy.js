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
import { parseArgs } from "util"
import { createWriteStream } from "fs"

const LogLevel = {
  TRACE: 0,
  DEBUG: 1,
  INFO: 2,
  WARN: 3,
  ERROR: 4,
  OFF: 5
}

const { values } = parseArgs({
  options: {
    "rpc-call-timeout": {
      type: "string",
      short: "t"
    },
    socket: {
      type: "string",
      short: "s"
    },
    "connection-timeout": {
      type: "string",
      short: "c"
    },
    "log-file": {
      type: "string",
      short: "l"
    },
    "log-level": {
      type: "string",
      short: "v"
    }
  },
  allowPositionals: false
})

const config = {
  ...values,
  "rpc-call-timeout": parseInt(values["rpc-call-timeout"], 10) || 60000,
  "connection-timeout": parseInt(values["connection-timeout"], 10) || 5000,
  "log-level": parseInt(values["log-level"], 10) ?? LogLevel.INFO
}

const stream = config["log-file"] ? createWriteStream(config["log-file"], { flags: "a" }) : null

/**
 * @param {...any} args
 * @returns {string}
 */
function splat(...args) {
  return args.map((a) => (typeof a === "object" ? JSON.stringify(a, null, 2) : String(a))).join(" ")
}

const log = {
  /**
   * @param {number} level
   * @param {string} levelName
   * @param {...any} args
   */
  _write(level, levelName, ...args) {
    if (stream && level >= config["log-level"]) {
      stream.write(`[${new Date().toISOString()}] [${levelName}] ${splat(...args)}\n`)
    }
  },
  trace: (...args) => log._write(LogLevel.TRACE, "TRACE", ...args),
  debug: (...args) => log._write(LogLevel.DEBUG, "DEBUG", ...args),
  info: (...args) => log._write(LogLevel.INFO, "INFO", ...args),
  warn: (...args) => log._write(LogLevel.WARN, "WARN", ...args),
  error: (...args) => log._write(LogLevel.ERROR, "ERROR", ...args),
  verbose: (...args) => log._write(LogLevel.DEBUG, "DEBUG", ...args),
  silly: (...args) => log._write(LogLevel.TRACE, "TRACE", ...args)
}

if (!config.socket) {
  throw new Error("--socket is required")
}

/**
 * Wrap a promise with a timeout
 * @template T
 * @param {Promise<T>} promise - The promise to wrap
 * @param {number} timeout - Timeout in milliseconds
 * @returns {Promise<T>}
 */
function withTimeout(promise, timeout) {
  return Promise.race([
    promise.then((result) => {
      return result
    }),
    new Promise((_, reject) => {
      AbortSignal.timeout(timeout).addEventListener("abort", (e) => {
        reject(e.target.reason)
      })
    })
  ])
}

/**
 * Connect to Neovim RPC socket
 * @returns {Promise<import("neovim").NeovimClient>}
 */
async function connect() {
  log.info("Attaching to Neovim RPC socket:", config.socket)

  // attach() is synchronous but may throw, wrap in Promise for timeout handling
  const client = await withTimeout(
    new Promise((resolve, reject) => {
      try {
        resolve(attach({ socket: config.socket, options: { logger: log } }))
      } catch (err) {
        reject(err)
      }
    }),
    config["connection-timeout"]
  )

  log.info("Attached to Neovim RPC socket:", config.socket)

  return client
}

/**
 * Fetch all servers from Neovim hub
 * @param {import("neovim").NeovimClient} nvim
 * @returns {Promise<object[]>}
 */
async function refresh(nvim) {
  log.trace("refreshing...")

  try {
    const servers = await nvim.lua('return require("mcphub.extensions.proxy").get_all_servers()')

    log.debug(`Loaded ${servers.length} MCP server(s): ${servers.map((s) => s.name).join(", ")}`)

    return servers
  } catch (error) {
    log.error("Failed to fetch servers from hub:", error.message)

    return []
  }
}

/**
 * Create and configure the MCP server
 * @param {import("neovim").NeovimClient} nvim
 * @returns {Promise<Server>}
 */
async function listen(nvim) {
  log.debug("Creating MCP server instance.")

  const server = new Server(
    {
      name: "mcphub-proxy",
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

  server.setRequestHandler(ListToolsRequestSchema, async () => {
    log.debug("ListTools request received.")

    const servers = await refresh(nvim)

    const all = []
    for (const s of servers) {
      for (const tool of s.capabilities.tools || []) {
        all.push({
          name: `${s.name}__${tool.name}`,
          description: tool.description || `${tool.name} from ${s.name}`,
          inputSchema: tool.inputSchema || { type: "object", properties: {} }
        })
      }
    }

    log.debug(`ListTools returning ${all.length} tools`)
    log.trace(
      "Tools list:",
      all.map((t) => t.name)
    )
    return { tools: all }
  })

  server.setRequestHandler(CallToolRequestSchema, async (request) => {
    const { name, arguments: args } = request.params

    log.debug(`CallTool request: ${name}`)
    log.trace("CallTool arguments:", args)

    const [serverName, ...toolParts] = name.split("__")
    const toolName = toolParts.join("__")

    try {
      log.trace("Calling proxy.call_tool via RPC...")
      const result = await withTimeout(
        nvim.lua(`return require("mcphub.extensions.proxy").call_tool(...)`, [
          serverName,
          toolName,
          { arguments: args || {}, caller: { type: "external", source: "proxy" } }
        ]),
        config["rpc-call-timeout"]
      )
      log.trace("RPC call completed")

      if (!result) {
        log.warn(`Tool ${name} returned null/undefined result`)
        throw new Error("Tool returned no result")
      }

      if (result.error) {
        log.warn(`Tool ${name} returned error: ${result.error}`)
        throw new Error(result.error)
      }

      log.debug(`CallTool ${name} succeeded with ${(result.content || []).length} content items`)
      log.trace("CallTool result:", result)

      return {
        content: result.content || []
      }
    } catch (error) {
      log.error(`CallTool ${name} failed:`, error.message)

      throw new Error(`Error calling tool: ${error.message}`)
    }
  })

  server.setRequestHandler(ListResourcesRequestSchema, async () => {
    log.debug("ListResources request received")
    const servers = await refresh(nvim)

    const all = []
    for (const mcpServer of servers) {
      for (const resource of mcpServer.capabilities.resources || []) {
        all.push({
          uri: `${mcpServer.name}://${resource.uri}`,
          name: resource.name || resource.uri,
          description: resource.description,
          mimeType: resource.mimeType
        })
      }
    }

    log.debug(`ListResources returning ${all.length} resources`)
    log.trace(
      "Resources list:",
      all.map((r) => r.uri)
    )

    return { resources: all }
  })

  server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
    const { uri } = request.params
    log.debug(`ReadResource request: ${uri}`)

    const match = uri.match(/^([^:]+):\/\/(.+)$/)
    if (!match) {
      throw new Error(`Invalid resource URI: ${uri}`)
    }

    const [, serverName, resourceUri] = match

    try {
      const result = await withTimeout(
        nvim.lua(`return require("mcphub.extensions.proxy").access_resource(...)`, [serverName, resourceUri, { caller: { type: "external", source: "proxy" } }]),
        config["rpc-call-timeout"]
      )

      if (!result) {
        throw new Error("Resource returned no result")
      }

      if (result.error) {
        throw new Error(result.error)
      }

      log.debug(`ReadResource ${uri} succeeded with ${(result.contents || []).length} content items`)
      log.trace("ReadResource result:", result)
      return {
        contents: result.contents || []
      }
    } catch (error) {
      throw new Error(`Error reading resource: ${error.message}`)
    }
  })

  server.setRequestHandler(ListPromptsRequestSchema, async () => {
    log.debug("ListPrompts request received")
    const servers = await refresh(nvim)

    const prompts = []
    for (const mcpServer of servers) {
      for (const prompt of mcpServer.capabilities.prompts || []) {
        prompts.push({
          name: `${mcpServer.name}__${prompt.name}`,
          description: prompt.description,
          arguments: prompt.arguments || []
        })
      }
    }

    log.debug(`ListPrompts returning ${prompts.length} prompts`)
    log.trace(
      "Prompts list:",
      prompts.map((p) => p.name)
    )

    return { prompts: prompts }
  })

  server.setRequestHandler(GetPromptRequestSchema, async (request) => {
    const { name, arguments: args } = request.params
    log.debug(`GetPrompt request: ${name}`)
    log.trace("GetPrompt arguments:", args)

    // Parse server and prompt name (format: servername__promptname)
    const [serverName, ...promptParts] = name.split("__")
    const promptName = promptParts.join("__")

    try {
      const result = await withTimeout(
        nvim.lua(`return require("mcphub.extensions.proxy").get_prompt(...)`, [
          serverName,
          promptName,
          { arguments: args || {}, caller: { type: "external", source: "proxy" } }
        ]),
        config["rpc-call-timeout"]
      )

      if (!result) {
        throw new Error("Prompt returned no result")
      }

      if (result.error) {
        throw new Error(result.error)
      }

      log.debug(`GetPrompt ${name} succeeded with ${(result.messages || []).length} messages`)
      log.trace("GetPrompt result:", result)

      return {
        messages: result.messages || [],
        description: result.description
      }
    } catch (error) {
      throw new Error(`Error getting prompt: ${error.message}`)
    }
  })

  log.debug("All request handlers registered.")

  return server
}

/**
 * Main entry point
 * @returns {Promise<void>}
 */
async function main() {
  log.info("Starting with config:", config)

  log.debug("Connecting to Neovim...")
  const nvim = await connect()
  log.info("Connected to Neovim.")

  log.debug("Creating MCP server...")
  const server = await listen(nvim)
  log.debug("MCP server created.")

  log.trace("Creating stdio transport...")
  const transport = new StdioServerTransport()

  log.debug("Connecting MCP server to stdio transport...")
  await server.connect(transport)
  log.info("MCP server running on stdio")
}

/** @returns {void} */
function cleanup() {
  log.trace("cleanup() called")
  if (stream) {
    log.trace("Closing log stream")
    stream.end()
  }
}

process.on("SIGINT", () => {
  log.info("Shutting down (SIGINT)...")
  log.debug("Received SIGINT signal")
  cleanup()

  process.exit(0)
})

process.on("SIGTERM", () => {
  log.info("Shutting down (SIGTERM)...")
  log.debug("Received SIGTERM signal")
  cleanup()

  process.exit(0)
})

// Start the server
main().catch((error) => {
  log.error("Fatal error:", error)
  process.stderr.write(`${error.message}\n${error.stack}\n`)

  process.exit(1)
})
