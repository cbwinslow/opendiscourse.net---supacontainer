import logging
from typing import Dict, Any, List, Optional, Type, Union, TypeVar
import logging
import importlib

from .base_backend import BaseStorageBackend
from ..data_models import (
    StorageConfig, StorageBackendType,
    Metric, Alert, AgentState, QueryOptions, QueryFilter
)

logger = logging.getLogger(__name__)

# Type variable for storage backends
T = TypeVar('T', bound=BaseStorageBackend)

class StorageBackendType(str, Enum):
    """Supported storage backend types"""
    POSTGRES = "postgres"
    TIMESCALE = "timescale"  # TimescaleDB (PostgreSQL extension)
    INFLUXDB = "influxdb"   # InfluxDB (time-series optimized)
    QDRANT = "qdrant"       # Qdrant (vector database)
    REDIS = "redis"         # Redis (in-memory)
    SQLITE = "sqlite"       # SQLite (file-based)

class StorageManager:
    """Manages multiple storage backends for metrics, alerts, and agent states"""
    
    def __init__(self):
        self.backends: Dict[str, BaseStorageBackend] = {}
        self.default_backend: Optional[str] = None
        self.initialized = False
    
    @classmethod
    def get_backend_class(cls, backend_type: Union[str, StorageBackendType]) -> Type[BaseStorageBackend]:
        """Get the backend class for the given backend type"""
        if isinstance(backend_type, str):
            backend_type = StorageBackendType(backend_type.lower())
        
        if backend_type == StorageBackendType.REDIS:
            from .redis_backend import RedisBackend
            return RedisBackend
        # Add other backend imports here as they're implemented
        # elif backend_type == StorageBackendType.POSTGRES:
        #     from .postgres_backend import PostgresBackend
        #     return PostgresBackend
        else:
            raise ValueError(f"Unsupported backend type: {backend_type}")
    
    async def initialize_backends(self, configs: List[StorageConfig]) -> bool:
        """Initialize multiple storage backends from a list of configurations
        
        Args:
            configs: List of storage configurations to initialize.
            
        Returns:
            bool: True if all backends were initialized successfully, False otherwise.
        """
        results = await asyncio.gather(
            *[self.initialize_backend(config) for config in configs],
            return_exceptions=True
        )
        
        success = all(isinstance(result, bool) and result for result in results)
        if not success:
            logger.warning("Some backends failed to initialize")
            
        return success
    
    async def initialize_backend(self, config: StorageConfig) -> bool:
        """Initialize a storage backend with the given configuration"""
        try:
            # Get backend class and create instance
            backend_class = self.get_backend_class(config.backend_type)
            backend = backend_class(config)
            
            # Connect to the backend
            await backend.connect()
            
            # Store the backend
            self.backends[config.name] = backend
            
            # Set as default if this is the first backend or explicitly configured
            if self.default_backend is None or config.default:
                self.default_backend = config.name
            
            self.initialized = True
            logger.info(f"Initialized {config.backend_type} backend: {config.name}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize {config.backend_type} backend: {str(e)}", exc_info=True)
            return False
    
    def get_backend(self, name: str = None) -> BaseStorageBackend:
        """Get a storage backend by name or the default backend
        
        Args:
            name: Optional name of the backend to get. If None, returns the default backend.
            
        Returns:
            The requested storage backend.
            
        Raises:
            ValueError: If no backend is found with the given name or no default backend is set.
        """
        if not name:
            name = self.default_backend
            
        if not name or name not in self.backends:
            raise ValueError(f"No backend found with name '{name}'. Available backends: {list(self.backends.keys())}")
            
        return self.backends[name]
    
    def get_backend_by_type(self, backend_type: Union[str, StorageBackendType]) -> BaseStorageBackend:
        """Get a storage backend by type
        
        Args:
            backend_type: Type of the backend to get.
            
        Returns:
            The first backend of the specified type.
            
        Raises:
            ValueError: If no backend of the specified type is found.
        """
        if isinstance(backend_type, str):
            backend_type = StorageBackendType(backend_type.lower())
            
        for backend in self.backends.values():
            if backend.config.backend_type == backend_type:
                return backend
                
        raise ValueError(f"No {backend_type} backend found. Available backends: {list(self.backends.keys())}")
    
    async def close(self):
        """Close all storage backends"""
        for name, backend in self.backends.items():
            try:
                await backend.close()
                logger.info(f"Closed storage backend: {name}")
            except Exception as e:
                logger.error(f"Error closing storage backend {name}: {str(e)}", exc_info=True)
        
        self.initialized = False
        self.backends = {}
        self.default_backend = None
    
    async def save_metric(self, metric: Metric, backend: str = None) -> bool:
        """Save a metric to the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return False
            
        try:
            return await self.backends[backend].save_metric(metric)
        except Exception as e:
            logger.error(f"Error saving metric to {backend}: {str(e)}", exc_info=True)
            return False
    
    async def get_metric(self, metric_id: str, backend: str = None) -> Optional[Metric]:
        """Get a metric by ID from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return None
            
        try:
            return await self.backends[backend].get_metric(metric_id)
        except Exception as e:
            logger.error(f"Error getting metric from {backend}: {str(e)}", exc_info=True)
            return None
    
    async def query_metrics(
        self,
        name: str = None,
        metric_type: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        tags: Dict[str, str] = None,
        options: QueryOptions = None,
        backend: str = None
    ) -> List[Metric]:
        """Query metrics with filters from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return []
            
        try:
            return await self.backends[backend].query_metrics(
                name=name,
                metric_type=metric_type,
                start_time=start_time,
                end_time=end_time,
                tags=tags,
                options=options
            )
        except Exception as e:
            logger.error(f"Error querying metrics from {backend}: {str(e)}", exc_info=True)
            return []
    
    async def save_alert(self, alert: Alert, backend: str = None) -> bool:
        """Save an alert to the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return False
            
        try:
            return await self.backends[backend].save_alert(alert)
        except Exception as e:
            logger.error(f"Error saving alert to {backend}: {str(e)}", exc_info=True)
            return False
    
    async def get_alert(self, alert_id: str, backend: str = None) -> Optional[Alert]:
        """Get an alert by ID from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return None
            
        try:
            return await self.backends[backend].get_alert(alert_id)
        except Exception as e:
            logger.error(f"Error getting alert from {backend}: {str(e)}", exc_info=True)
            return None
    
    async def query_alerts(
        self,
        status: str = None,
        severity: str = None,
        source: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        labels: Dict[str, str] = None,
        options: QueryOptions = None,
        backend: str = None
    ) -> List[Alert]:
        """Query alerts with filters from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return []
            
        try:
            return await self.backends[backend].query_alerts(
                status=status,
                severity=severity,
                source=source,
                start_time=start_time,
                end_time=end_time,
                labels=labels,
                options=options
            )
        except Exception as e:
            logger.error(f"Error querying alerts from {backend}: {str(e)}", exc_info=True)
            return []
    
    async def save_agent_state(self, state: AgentState, backend: str = None) -> bool:
        """Save an agent state to the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return False
            
        try:
            return await self.backends[backend].save_agent_state(state)
        except Exception as e:
            logger.error(f"Error saving agent state to {backend}: {str(e)}", exc_info=True)
            return False
    
    async def get_agent_state(self, agent_id: str, backend: str = None) -> Optional[AgentState]:
        """Get the latest state for an agent from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return None
            
        try:
            return await self.backends[backend].get_agent_state(agent_id)
        except Exception as e:
            logger.error(f"Error getting agent state from {backend}: {str(e)}", exc_info=True)
            return None
    
    async def get_agent_states(
        self,
        status: str = None,
        last_heartbeat_after: datetime = None,
        options: QueryOptions = None,
        backend: str = None
    ) -> List[AgentState]:
        """Query agent states with filters from the specified backend"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return []
            
        try:
            return await self.backends[backend].get_agent_states(
                status=status,
                last_heartbeat_after=last_heartbeat_after,
                options=options
            )
        except Exception as e:
            logger.error(f"Error querying agent states from {backend}: {str(e)}", exc_info=True)
            return []
    
    async def get_metric_history(
        self,
        metric_name: str,
        start_time: datetime = None,
        end_time: datetime = None,
        step: timedelta = None,
        aggregation: str = "avg",  # avg, min, max, sum, count
        backend: str = None
    ) -> List[Dict[str, Any]]:
        """Get historical metric data with optional downsampling"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return []
            
        try:
            if hasattr(self.backends[backend], 'get_metric_history'):
                return await self.backends[backend].get_metric_history(
                    metric_name=metric_name,
                    start_time=start_time,
                    end_time=end_time,
                    step=step,
                    aggregation=aggregation
                )
            else:
                # Fallback to querying raw metrics if get_metric_history is not implemented
                metrics = await self.query_metrics(
                    name=metric_name,
                    start_time=start_time,
                    end_time=end_time,
                    backend=backend
                )
                
                if not metrics:
                    return []
                    
                # Simple aggregation by timestamp
                result = []
                for metric in metrics:
                    for value in metric.values:
                        result.append({
                            'timestamp': value.timestamp,
                            'value': value.value,
                            'tags': value.tags
                        })
                
                return result
                
        except Exception as e:
            logger.error(f"Error getting metric history from {backend}: {str(e)}", exc_info=True)
            return []
    
    async def backup_database(self, backup_path: str, backend: str = None) -> bool:
        """Create a backup of the database"""
        if backend is None:
            backend = self.default_backend
            
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return False
            
        try:
            if hasattr(self.backends[backend], 'backup_database'):
                return await self.backends[backend].backup_database(backup_path)
            else:
                logger.warning(f"Backup not supported for {self.backends[backend].__class__.__name__}")
                return False
        except Exception as e:
            logger.error(f"Error creating database backup: {str(e)}", exc_info=True)
            return False
    
    async def restore_database(self, backup_path: str, backend: str = "default") -> bool:
        """Restore the database from a backup"""
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return False
            
        try:
            if hasattr(self.backends[backend], 'restore_database'):
                return await self.backends[backend].restore_database(backup_path)
            else:
                logger.warning(f"Restore not supported for {self.backends[backend].__class__.__name__}")
                return False
        except Exception as e:
            logger.error(f"Error restoring database from backup: {str(e)}", exc_info=True)
            return False
    
    async def get_database_stats(self, backend: str = "default") -> Dict[str, Any]:
        """Get database statistics"""
        if backend not in self.backends:
            logger.error(f"Backend not found: {backend}")
            return {}
            
        try:
            if hasattr(self.backends[backend], 'get_database_stats'):
                return await self.backends[backend].get_database_stats()
            else:
                # Return basic stats if not implemented by the backend
                return {
                    'backend': str(self.backends[backend].__class__.__name__),
                    'metrics_count': len(await self.query_metrics(backend=backend)),
                    'alerts_count': len(await self.query_alerts(backend=backend)),
                    'agent_states_count': len(await self.get_agent_states(backend=backend)),
                    'supports_backup': hasattr(self.backends[backend], 'backup_database'),
                    'supports_restore': hasattr(self.backends[backend], 'restore_database')
                }
        except Exception as e:
            logger.error(f"Error getting database stats: {str(e)}", exc_info=True)
            return {}


# Example usage
async def example_usage():
    # Configure storage backends
    configs = {
        "timeseries": StorageBackendConfig(
            type=StorageBackendType.TIMESCALE,
            connection_string="postgresql://user:password@localhost:5432/monitoring",
            options={
                "time_partition_interval": "1 day",
                "replication_factor": 2
            }
        ),
        "vector": StorageBackendConfig(
            type=StorageBackendType.QDRANT,
            connection_string="http://localhost:6333",
            options={
                "collection_name": "monitoring_embeddings",
                "vector_size": 384
            }
        )
    }
    
    # Initialize the storage manager
    storage = StorageManager(configs)
    await storage.initialize()
    
    try:
        # Example: Save a metric
        from datetime import datetime, timezone
        from ..data_models import Metric, MetricValue
        
        metric = Metric(
            name="cpu.usage",
            type="cpu",
            description="CPU usage percentage",
            unit="percent"
        )
        
        metric.add_value(
            value=75.5,
            timestamp=datetime.now(timezone.utc),
            tags={"host": "server1", "core": "0"}
        )
        
        await storage.save_metric(metric, backend="timeseries")
        
        # Example: Query metrics
        metrics = await storage.query_metrics(
            name="cpu.usage",
            start_time=datetime.now(timezone.utc) - timedelta(hours=1),
            backend="timeseries"
        )
        
        print(f"Found {len(metrics)} metrics")
        
    finally:
        # Clean up
        await storage.close()


if __name__ == "__main__":
    import asyncio
    asyncio.run(example_usage())
