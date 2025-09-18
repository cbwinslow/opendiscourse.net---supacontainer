import { McpServer } from '@modelcontextprotocol/sdk';
import { Router, IRequest } from 'itty-router';

declare const Response: typeof globalThis.Response;
declare const Request: typeof globalThis.Request;
interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

// Initialize the MCP server
const server = new McpServer();
const router = Router();

// Tool 1: Text Processing Tool
server.tool('text-processor', {
  description: 'Processes text with various operations',
  parameters: {
    type: 'object',
    properties: {
      text: { type: 'string', description: 'The text to process' },
      operation: { 
        type: 'string', 
        enum: ['uppercase', 'lowercase', 'reverse', 'word-count'],
        description: 'The operation to perform on the text'
      }
    },
    required: ['text', 'operation']
  },
  handler: async ({ text, operation }: { text: string; operation: string }) => {
    switch (operation) {
      case 'uppercase':
        return { result: text.toUpperCase() };
      case 'lowercase':
        return { result: text.toLowerCase() };
      case 'reverse':
        return { result: text.split('').reverse().join('') };
      case 'word-count':
        return { result: text.split(/\s+/).filter(Boolean).length };
      default:
        throw new Error(`Unsupported operation: ${operation}`);
    }
  }
});

// Tool 2: Math Operations
server.tool('math', {
  description: 'Performs mathematical operations',
  parameters: {
    type: 'object',
    properties: {
      operation: { 
        type: 'string',
        enum: ['add', 'subtract', 'multiply', 'divide', 'power', 'sqrt'],
        description: 'The mathematical operation to perform'
      },
      numbers: {
        type: 'array',
        items: { type: 'number' },
        description: 'Numbers to perform the operation on'
      }
    },
    required: ['operation', 'numbers']
  },
  handler: async ({ operation, numbers }: { operation: string; numbers: number[] }) => {
    if (!Array.isArray(numbers) || numbers.length === 0) {
      throw new Error('At least one number is required');
    }

    switch (operation) {
      case 'add':
        return { result: numbers.reduce((a, b) => a + b, 0) };
      case 'subtract':
        return { result: numbers.reduce((a, b) => a - b) };
      case 'multiply':
        return { result: numbers.reduce((a, b) => a * b, 1) };
      case 'divide':
        if (numbers.slice(1).some(n => n === 0)) {
          throw new Error('Cannot divide by zero');
        }
        return { result: numbers.reduce((a, b) => a / b) };
      case 'power':
        return { result: Math.pow(numbers[0], numbers[1] || 2) };
      case 'sqrt':
        return { result: Math.sqrt(numbers[0]) };
      default:
        throw new Error(`Unsupported operation: ${operation}`);
    }
  }
});

// Tool 3: Data Format Converter
server.tool('converter', {
  description: 'Converts between different data formats',
  parameters: {
    type: 'object',
    properties: {
      input: { type: 'string', description: 'The input data' },
      from: { 
        type: 'string', 
        enum: ['json', 'yaml', 'csv', 'xml'],
        description: 'Input format'
      },
      to: { 
        type: 'string', 
        enum: ['json', 'yaml', 'csv', 'xml'],
        description: 'Output format'
      }
    },
    required: ['input', 'from', 'to']
  },
  handler: async ({ input, from, to }: { input: string; from: string; to: string }) => {
    // In a real implementation, you would use proper parsing libraries
    return {
      result: `Converted from ${from} to ${to}`,
      warning: 'This is a mock implementation. In a real app, use proper parsing libraries.'
    };
  }
});

// Tool 4: HTTP Request Tool
server.tool('http-request', {
  description: 'Makes HTTP requests',
  parameters: {
    type: 'object',
    properties: {
      url: { type: 'string', description: 'The URL to request' },
      method: { 
        type: 'string', 
        enum: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH'],
        default: 'GET',
        description: 'HTTP method to use'
      },
      headers: { 
        type: 'object',
        additionalProperties: { type: 'string' },
        description: 'HTTP headers to include in the request'
      },
      body: { 
        type: 'string',
        description: 'Request body for POST/PUT/PATCH requests'
      }
    },
    required: ['url']
  },
  handler: async ({ url, method = 'GET', headers = {}, body }: { 
    url: string; 
    method?: string; 
    headers?: Record<string, string>; 
    body?: string 
  }) => {
    const response = await fetch(url, {
      method,
      headers,
      body: method !== 'GET' && method !== 'HEAD' ? body : undefined
    });
    
    const responseText = await response.text();
    
    return {
      status: response.status,
      statusText: response.statusText,
      headers: Object.fromEntries(response.headers.entries()),
      body: responseText
    };
  }
});

// Health check endpoint
router.get('/health', () => new Response(JSON.stringify({ status: 'ok' }), {
  headers: { 'Content-Type': 'application/json' }
}));

// Handle MCP requests
router.all('*', async (request) => {
  try {
    const result = await server.handleRequest(request);
    return new Response(JSON.stringify(result), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error.message || 'An error occurred'
    }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});

// Cloudflare Workers entry point
export default {
  async fetch(request: Request, env: any, ctx: ExecutionContext): Promise<Response> {
    return router.handle(request);
  }
};
