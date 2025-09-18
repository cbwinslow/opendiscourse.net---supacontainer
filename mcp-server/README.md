# MCP Server for Cloudflare Workers

A Model Context Protocol (MCP) server with various tools, deployable to Cloudflare Workers.

## Features

- Text processing (uppercase, lowercase, reverse, word count)
- Mathematical operations (add, subtract, multiply, divide, power, sqrt)
- Data format conversion (JSON, YAML, CSV, XML)
- HTTP request tool
- Health check endpoint

## Prerequisites

- Node.js 18+
- npm or yarn
- Cloudflare Wrangler CLI (`npm install -g wrangler`)
- Cloudflare account

## Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   npm install
   ```

## Development

1. Start the development server:
   ```bash
   npm run dev
   ```

2. The server will be available at `http://localhost:8787`

## Building

To build the project:

```bash
npm run build
```

## Deployment

1. Login to Cloudflare (if not already logged in):
   ```bash
   npx wrangler login
   ```

2. Deploy to Cloudflare Workers:
   ```bash
   npm run deploy
   ```

## Usage

### Text Processing

```json
{
  "tool": "text-processor",
  "parameters": {
    "text": "Hello, World!",
    "operation": "uppercase"
  }
}
```

### Math Operations

```json
{
  "tool": "math",
  "parameters": {
    "operation": "add",
    "numbers": [5, 10, 15]
  }
}
```

### HTTP Request

```json
{
  "tool": "http-request",
  "parameters": {
    "url": "https://api.example.com/data",
    "method": "GET",
    "headers": {
      "Authorization": "Bearer YOUR_TOKEN"
    }
  }
}
```

## Health Check

```
GET /health
```

## Environment Variables

- `NODE_ENV`: Set to 'production' for production
- `ENABLE_LOGGING`: Set to 'true' to enable request logging

## License

MIT
