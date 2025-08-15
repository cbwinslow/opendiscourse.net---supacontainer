#!/usr/bin/env python3
"""
Example demonstrating how to use the Redis backend with StorageManager.

This script shows how to:
1. Initialize the StorageManager with a Redis backend
2. Save and retrieve metrics
3. Save and retrieve alerts
4. Save and retrieve agent states
5. Query data from the Redis backend
"""
import asyncio
import json
from datetime import datetime, timedelta

from ai_agents.data_models import (
    StorageConfig, StorageBackendType, 
    Metric, Alert, AgentState, MetricValue,
    AlertSeverity, AlertStatus, AgentStatus,
    QueryOptions
)
from ai_agents.storage.manager import StorageManager

# Configuration for Redis backend
REDIS_CONFIG = StorageConfig(
    name="redis-storage",
    backend_type=StorageBackendType.REDIS,
    connection_string="redis://localhost:6379/0",
    default=True,
    options={
        "metric_ttl_seconds": 86400,  # 1 day
        "alert_ttl_seconds": 172800,  # 2 days
        "agent_state_ttl_seconds": 3600,  # 1 hour
    }
)

async def main():
    print("=== Redis Backend Example ===\n")
    
    # Initialize StorageManager
    storage = StorageManager()
    
    try:
        # Initialize the Redis backend
        print("Initializing Redis backend...")
        await storage.initialize_backend(REDIS_CONFIG)
        
        # Example 1: Working with Metrics
        print("\n--- Working with Metrics ---")
        
        # Create a sample metric
        metric = Metric(
            id="example-metric-1",
            name="system.cpu.usage",
            type="gauge",
            values=[
                MetricValue(
                    timestamp=datetime.utcnow(),
                    value=45.2,
                    tags={"host": "example-host-1", "region": "us-west-1"}
                )
            ],
            metadata={"unit": "percent", "description": "CPU usage percentage"}
        )
        
        # Save the metric
        print(f"Saving metric: {metric.name}")
        await storage.save_metric(metric)
        
        # Retrieve the metric
        print(f"Retrieving metric: {metric.id}")
        retrieved_metric = await storage.get_metric(metric.id)
        print(f"Retrieved metric: {retrieved_metric.name} = {retrieved_metric.values[0].value}%")
        
        # Example 2: Working with Alerts
        print("\n--- Working with Alerts ---")
        
        # Create a sample alert
        alert = Alert(
            id="example-alert-1",
            name="High CPU Usage",
            description="CPU usage is above 80%",
            severity=AlertSeverity.WARNING,
            status=AlertStatus.FIRING,
            source="monitoring-agent-1",
            start_time=datetime.utcnow(),
            labels={"severity": "warning", "service": "example-service"},
            annotations={"summary": "High CPU usage detected"}
        )
        
        # Save the alert
        print(f"Saving alert: {alert.name}")
        await storage.save_alert(alert)
        
        # Retrieve the alert
        print(f"Retrieving alert: {alert.id}")
        retrieved_alert = await storage.get_alert(alert.id)
        print(f"Retrieved alert: {retrieved_alert.name} - {retrieved_alert.status}")
        
        # Example 3: Working with Agent States
        print("\n--- Working with Agent States ---")
        
        # Create a sample agent state
        agent_state = AgentState(
            id="example-agent-state-1",
            agent_id="monitoring-agent-1",
            status=AgentStatus.RUNNING,
            metrics={"cpu": 15.5, "memory_mb": 512, "queue_size": 5},
            last_heartbeat=datetime.utcnow()
        )
        
        # Save the agent state
        print(f"Saving agent state for: {agent_state.agent_id}")
        await storage.save_agent_state(agent_state)
        
        # Retrieve the agent state
        print(f"Retrieving agent state for: {agent_state.agent_id}")
        retrieved_state = await storage.get_agent_state(agent_state.agent_id)
        print(f"Retrieved agent state - Status: {retrieved_state.status}, CPU: {retrieved_state.metrics.get('cpu')}%")
        
        # Example 4: Querying Data
        print("\n--- Querying Data ---")
        
        # Add more metrics for querying
        for i in range(5):
            metric = Metric(
                id=f"example-metric-{i+2}",
                name=f"system.memory.usage",
                type="gauge",
                values=[
                    MetricValue(
                        timestamp=datetime.utcnow() - timedelta(minutes=i*5),
                        value=60 + (i * 5),  # 60%, 65%, 70%, 75%, 80%
                        tags={"host": f"example-host-{i%2 + 1}", "region": "us-west-1"}
                    )
                ]
            )
            await storage.save_metric(metric)
        
        # Query metrics by name
        print("\nQuerying metrics by name:")
        metrics = await storage.query_metrics(
            name="system.memory.usage",
            options=QueryOptions(limit=3)
        )
        
        for m in metrics:
            print(f"- {m.name} (host: {m.values[0].tags.get('host')}): {m.values[0].value}%")
        
        # Get database stats
        print("\nDatabase statistics:")
        stats = await storage.get_backend().get_database_stats()
        print(json.dumps(stats, indent=2))
        
    finally:
        # Clean up
        print("\nCleaning up...")
        await storage.close()

if __name__ == "__main__":
    asyncio.run(main())
