#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create docs directory if it doesn't exist
mkdir -p docs/api

echo -e "${YELLOW}Generating API documentation...${NC}"

# Generate OpenAPI/Swagger documentation for AI Orchestrator
cat > docs/api/openapi.yaml << 'EOL'
openapi: 3.0.0
info:
  title: AI Orchestrator API
  description: API documentation for the AI Orchestrator service
  version: 1.0.0
  contact:
    name: API Support
    email: support@opendiscourse.net
  license:
    name: Apache 2.0
    url: https://www.apache.org/licenses/LICENSE-2.0.html

servers:
  - url: https://api.opendiscourse.net/v1
    description: Production server
  - url: http://localhost:8000/v1
    description: Development server

components:
  securitySchemes:
    BearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  schemas:
    Error:
      type: object
      properties:
        error:
          type: string
          description: Error message
        code:
          type: integer
          format: int32
          description: HTTP status code
    Message:
      type: object
      properties:
        message_type:
          type: string
          enum: [metric, log, alert, command, response]
          description: Type of the message
        source:
          type: string
          description: Source of the message
        timestamp:
          type: string
          format: date-time
          description: Timestamp of the message
        content:
          type: object
          description: Message content
        severity:
          type: string
          enum: [debug, info, warning, error, critical]
          description: Severity level

paths:
  /health:
    get:
      summary: Health check
      description: Check if the service is running
      responses:
        '200':
          description: Service is healthy
          content:
            application/json:
              schema:
                type: object
                properties:
                  status:
                    type: string
                    example: "healthy"
  /v1/messages:
    post:
      summary: Send a message
      description: Send a message to the orchestrator
      security:
        - BearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/Message'
      responses:
        '202':
          description: Message accepted
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: string
                    format: uuid
                    description: Message ID
                  status:
                    type: string
                    example: "accepted"
  /v1/agents:
    get:
      summary: List agents
      description: Get a list of all registered agents
      security:
        - BearerAuth: []
      responses:
        '200':
          description: List of agents
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Agent'
    post:
      summary: Register a new agent
      description: Register a new agent with the orchestrator
      security:
        - BearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/AgentRegistration'
      responses:
        '201':
          description: Agent registered successfully
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Agent'
  /v1/agents/{agent_id}:
    get:
      summary: Get agent details
      description: Get details for a specific agent
      security:
        - BearerAuth: []
      parameters:
        - name: agent_id
          in: path
          required: true
          schema:
            type: string
          description: ID of the agent
      responses:
        '200':
          description: Agent details
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Agent'
    delete:
      summary: Unregister an agent
      description: Unregister an agent from the orchestrator
      security:
        - BearerAuth: []
      parameters:
        - name: agent_id
          in: path
          required: true
          schema:
            type: string
          description: ID of the agent to unregister
      responses:
        '204':
          description: Agent unregistered successfully
  /v1/metrics:
    get:
      summary: Get metrics
      description: Get system and application metrics
      security:
        - BearerAuth: []
      responses:
        '200':
          description: Metrics data
          content:
            text/plain:
              schema:
                type: string
  /v1/alerts:
    get:
      summary: List alerts
      description: Get a list of active alerts
      security:
        - BearerAuth: []
      responses:
        '200':
          description: List of alerts
          content:
            application/json:
              schema:
                type: array
                items:
                  $ref: '#/components/schemas/Alert'
  /v1/logs:
    get:
      summary: Query logs
      description: Query system and application logs
      security:
        - BearerAuth: []
      parameters:
        - name: query
          in: query
          schema:
            type: string
          description: LogQL query string
        - name: limit
          in: query
          schema:
            type: integer
            default: 100
          description: Maximum number of log entries to return
        - name: start
          in: query
          schema:
            type: string
            format: date-time
          description: Start time for the query
        - name: end
          in: query
          schema:
            type: string
            format: date-time
          description: End time for the query
      responses:
        '200':
          description: Log entries
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/LogResponse'

definitions:
  Agent:
    type: object
    properties:
      id:
        type: string
        format: uuid
        description: Unique identifier for the agent
      name:
        type: string
        description: Name of the agent
      type:
        type: string
        description: Type of the agent
      status:
        type: string
        enum: [online, offline, error]
        description: Current status of the agent
      last_seen:
        type: string
        format: date-time
        description: Last time the agent was seen
      capabilities:
        type: array
        items:
          type: string
        description: List of capabilities supported by the agent
      metadata:
        type: object
        additionalProperties: true
        description: Additional metadata about the agent
  AgentRegistration:
    type: object
    required:
      - name
      - type
    properties:
      name:
        type: string
        description: Name of the agent
      type:
        type: string
        description: Type of the agent
      capabilities:
        type: array
        items:
          type: string
        description: List of capabilities supported by the agent
      metadata:
        type: object
        additionalProperties: true
        description: Additional metadata about the agent
  Alert:
    type: object
    properties:
      id:
        type: string
        format: uuid
        description: Unique identifier for the alert
      name:
        type: string
        description: Name of the alert
      status:
        type: string
        enum: [firing, resolved, inactive]
        description: Current status of the alert
      severity:
        type: string
        enum: [none, low, medium, high, critical]
        description: Severity of the alert
      startsAt:
        type: string
        format: date-time
        description: When the alert started
      endsAt:
        type: string
        format: date-time
        description: When the alert ended (if resolved)
      labels:
        type: object
        additionalProperties:
          type: string
        description: Labels for the alert
      annotations:
        type: object
        additionalProperties:
          type: string
        description: Annotations for the alert
  LogResponse:
    type: object
    properties:
      streams:
        type: array
        items:
          type: object
          properties:
            stream:
              type: object
              additionalProperties:
                type: string
              description: Labels for the log stream
            values:
              type: array
              items:
                type: array
                items:
                  type: string
                minItems: 2
                maxItems: 2
                description: Array of [timestamp, log line] pairs
      status:
        type: string
        enum: [success, error]
        description: Status of the query

externalDocs:
  description: Find more info here
  url: https://docs.opendiscourse.net
EOL

# Generate Markdown documentation from OpenAPI spec
echo -e "${YELLOW}Generating Markdown documentation...${NC}"

# Install redoc-cli if not already installed
if ! command -v redoc-cli &> /dev/null; then
  echo -e "${YELLOW}Installing redoc-cli...${NC}"
  npm install -g redoc-cli
fi

# Generate HTML documentation
redoc-cli bundle docs/api/openapi.yaml -o docs/api/index.html

# Generate Markdown documentation
npm install -g widdershins
widdershins --search false --language_tabs 'shell:Shell' 'http:HTTP' 'javascript:JavaScript' 'python:Python' -o docs/API.md docs/api/openapi.yaml

echo -e "${GREEN}API documentation generated successfully!${NC}"
echo -e "- HTML documentation: ${YELLOW}docs/api/index.html${NC}"
echo -e "- Markdown documentation: ${YELLOW}docs/API.md${NC}"

# Generate Python client library
echo -e "${YELLOW}Generating Python client library...${NC}"
pip install openapi-python-client
openapi-python-client generate --path docs/api/openapi.yaml --config .openapi-python-client.yml

# Generate TypeScript client library
echo -e "${YELLOW}Generating TypeScript client library...${NC}"
npm install -g @openapitools/openapi-generator-cli
openapi-generator-cli generate -i docs/api/openapi.yaml -g typescript-axios -o clients/typescript --skip-validate-spec

echo -e "${GREEN}Client libraries generated successfully!${NC}"
echo -e "- Python client: ${YELLOW}clients/python${NC}"
echo -e "- TypeScript client: ${YELLOW}clients/typescript${NC}"
