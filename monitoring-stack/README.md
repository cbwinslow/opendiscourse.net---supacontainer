# AI-Powered Monitoring and Orchestration Stack

This stack provides comprehensive monitoring, logging, and AI-driven orchestration for the OpenDiscourse platform.

## Components

- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **OpenSearch**: Log and event storage
- **RabbitMQ**: Message broker for AI agents
- **AI Orchestrator**: Central brain for automated operations
- **Agent Framework**: For deploying specialized AI agents

## Getting Started

1. Copy `.env.example` to `.env` and configure your environment variables
2. Run `docker-compose up -d` to start all services
3. Access the services through the configured domain

## Architecture

```
┌─────────────────┐     ┌───────────────┐     ┌─────────────┐
│   Prometheus    │◄────┤   Grafana    │     │  OpenSearch  │
└────────┬────────┘     └──────┬───────┘     └──────┬──────┘
         │                     │                     │
         ▼                     ▼                     ▼
┌─────────────────┐     ┌───────────────┐     ┌─────┴────────┐
│  AI Orchestrator │◄───►│   RabbitMQ    │◄────┤    Loki     │
└────────┬─────────┘     └──────┬───────┘     └─────────────┘
         │                      │
         ▼                      ▼
┌─────────────────┐     ┌───────────────┐
│  Agent Manager  │     │  API Gateway  │
└─────────────────┘     └───────────────┘
```
