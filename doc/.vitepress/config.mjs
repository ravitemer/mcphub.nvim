import { defineConfig } from "vitepress";
import { execSync } from "node:child_process";
import { withMermaid } from "vitepress-plugin-mermaid";

const inProd = process.env.NODE_ENV === "production";

let version = "Main";
if (inProd) {
  try {
    version = execSync("git describe --tags --abbrev=0", {
      encoding: "utf-8",
    }).trim();
  } catch (error) {
    console.warn("Failed to get git version, using default.");
  }
}

const baseHeaders = [
  ['link', { rel: 'icon', href: 'https://github.com/user-attachments/assets/5cdf9d69-3de7-458b-a670-5153a97c544a' }]  // put favicon.ico in public directory, if base is set, use /base/favicon.ico
];
const umamiScript = [
  "script",
  {
    defer: "true",
    src: "https://cloud.umami.is/script.js",
    "data-website-id": "a080d520-2689-406a-bee3-c45c44b2d70e",
  },
];
const headers = inProd ? [...baseHeaders, umamiScript] : baseHeaders;

const siteUrl = "https://ravitemer.github.io/mcphub.nvim/";
// https://vitepress.dev/reference/site-config
export default withMermaid(
  defineConfig({
    title: "MCP HUB",
    description: "A powerful Neovim plugin that integrates MCP (Model Context Protocol) servers into your workflow. Configure and manage MCP servers through a centralized config file while providing an intuitive UI for browsing, installing and testing tools and resources. Perfect for LLM integration, offering both programmatic API access and interactive testing capabilities through the `:MCPHub` command.",
    mermaid: {
      securityLevel: "loose", // Allows more flexibility
      theme: "base", // Use base theme to allow CSS variables to take effect
    },
    head: headers,
    base: "/mcphub.nvim/",
    sitemap: { hostname: siteUrl },
    themeConfig: {
      sponsors: {
        enabled: true,
        cards: [
          {
            href: "https://www.warp.dev/mcp-hub-nvim",
            image: "/mcphub.nvim/sponsors/warp.png",
            text: "Warp, the Intelligent Terminal. Run mcphub.nvim in Warp today",
            alt: "Warp Terminal"
          },
          {
            href: "https://dub.sh/composio-mcp",
            image: "/mcphub.nvim/sponsors/composio-logo.png",
            text: "Instantly Connect to  100+ Managed MCP Servers with Built-In Auth",
            alt: "Composio"
          },
        ]
      },
      logo: "https://github.com/user-attachments/assets/5cdf9d69-3de7-458b-a670-5153a97c544a",
      nav: [
        {
          text: `${version}`,
          items: [
            {
              text: "Changelog",
              link: "https://github.com/ravitemer/mcphub.nvim/blob/main/CHANGELOG.md",
            },
            {
              text: "Contributing",
              link: "https://github.com/ravitemer/mcphub.nvim/blob/main/CONTRIBUTING.md",
            },
          ],
        },
      ],

      sidebar: [
        { text: "Getting started", link: "/" },
        {
          text: "Setup",
          collapsed: false,
          items: [
            { text: "Installation", link: "/installation" },
            { text: "Configuration", link: "/configuration" },
          ]
        },
        {
          text: "MCP Servers",
          collapsed: false,
          items: [
            { text: "servers.json", link: "/mcp/servers_json" },
            {
              text: "Lua MCP Servers",
              collapsed: true,
              items: [
                { text: "Why", link: "/mcp/native/" },
                { text: "Registration", link: "/mcp/native/registration" },
                { text: "Add Tools", link: "/mcp/native/tools" },
                { text: "Add Resources", link: "/mcp/native/resources" },
                { text: "Add Prompts", link: "/mcp/native/prompts" },
                { text: "Best Practices", link: "/mcp/native/best-practices" },
              ],
            },
          ]
        },
        {
          text: "Extensions",
          collapsed: false,
          items: [
            { text: "Avante", link: "/extensions/avante" },
            { text: "CodeCompanion", link: "/extensions/codecompanion" },
            { text: "CopilotChat", link: "/extensions/copilotchat" },
            { text: "Lualine", link: "/extensions/lualine" },
          ],
        },
        {
          text: "Other",
          collapsed: false,
          items: [
            { text: "Showcase", link: "/other/demos" },
            { text: "API", link: "/other/api" },
            { text: "How it works", link: "/other/architecture" },
            { text: "Troubleshooting", link: "/other/troubleshooting" },
          ],
        },
      ],
      outline: {
        level: [2, 3],
      },
      editLink: {
        pattern:
          "https://github.com/ravitemer/mcphub.nvim/edit/main/doc/:path",
        text: "Edit this page on GitHub",
      },

      footer: {
        message: "Released under the MIT License.",
        copyright: "Copyright © 2025-present Ravitemer",
      },

      socialLinks: [
        {
          icon: "githubsponsors",
          link: "https://github.com/sponsors/ravitemer",
        },
        {
          icon: "discord",
          link: "https://discord.gg/NTqfxXsNuN",
        },
        {
          icon: "x",
          link: "https://x.com/ravitemer",
        },
        {
          icon: "github",
          link: "https://github.com/ravitemer/mcphub.nvim",
        },
      ],
      // lastUpdated: true,
      search: { provider: "local" },
    },
  }))
