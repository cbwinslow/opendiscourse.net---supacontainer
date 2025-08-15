# Storage Backends

This directory contains implementations of various storage backends for the AI monitoring system.

## Available Backends

### Redis Backend (`redis_backend.py`)

A high-performance, in-memory database backend using Redis. Ideal for fast access to metrics, alerts, and agent states.

#### Features

- **Fast in-memory storage** with configurable TTL for automatic data expiration
- **Persistence** with optional disk-based snapshots
- **High availability** with Redis Sentinel or Redis Cluster
- **Pub/Sub capabilities** for real-time updates

#### Configuration

Example configuration:

```python
from ai_agents.data_models import StorageConfig, StorageBackendType

config = StorageConfig(
    name="redis-storage",
    backend_type=StorageBackendType.REDIS,
    connection_string="redis://localhost:6379/0",
    default=True,
    options={
        "metric_ttl_seconds": 86400,  # 1 day
        "alert_ttl_seconds": 172800,  # 2 days
        "agent_state_ttl_seconds": 3600,  # 1 hour
        "max_connections": 10,  # Optional: max connection pool size
    }
)
```

#### Usage

```python
from ai_agents.storage.manager import StorageManager

# Initialize the storage manager with Redis backend
storage = StorageManager()
await storage.initialize_backend(config)

# Save a metric
metric = Metric(
    id="example-metric-1",
    name="system.cpu.usage",
    type="gauge",
    values=[MetricValue(timestamp=datetime.utcnow(), value=45.2)]
)
await storage.save_metric(metric)

# Query metrics
metrics = await storage.query_metrics(name="system.cpu.usage")
```

## Implementing a New Backend

To implement a new storage backend:

1. Create a new file in this directory (e.g., `my_backend.py`)
2. Implement the `BaseStorageBackend` interface
3. Add the backend to the `StorageManager.get_backend_class()` method
4. Update the `StorageBackendType` enum in `data_models.py`
5. Add tests in the `tests` directory

## Performance Considerations

- **Redis**: Best for high-throughput, low-latency access to recent data
- **PostgreSQL/TimescaleDB**: Better for historical data analysis and complex queries
- **Qdrant**: Ideal for similarity search and vector operations

## Data Retention

Each backend handles data retention differently:

- **Redis**: Uses TTL-based expiration
- **PostgreSQL**: Can use table partitioning for time-series data
- **InfluxDB**: Built-in retention policies

## Backup and Recovery

Each backend should implement its own backup and recovery strategy:

```python
# Create a backup
await storage.backup_database("/path/to/backup")

# Restore from backup (implementation dependent on backend)
# Example for Redis: Use redis-cli --rdb /path/to/dump.rdb
```

## Monitoring

Database statistics can be retrieved using:

```python
stats = await storage.get_database_stats()
print(f"Backend: {stats['backend']}")
print(f"Version: {stats.get('version', 'unknown')}")
print(f"Uptime: {stats.get('uptime_seconds', 0)} seconds")
```
