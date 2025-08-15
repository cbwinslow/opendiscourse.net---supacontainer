import json
import logging
import asyncio
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional, Union, Set

import aioredis
from aioredis import Redis, ConnectionPool

from ..data_models import (
    Metric, Alert, AgentState, QueryOptions, QueryFilter,
    StorageConfig, StorageBackendType, MONITORING_SCHEMA
)
from .base_backend import BaseStorageBackend

logger = logging.getLogger(__name__)

class RedisBackend(BaseStorageBackend):
    """Redis storage backend for metrics, alerts, and agent states"""
    
    def __init__(self, config: StorageConfig):
        super().__init__(config)
        self.redis: Optional[Redis] = None
        self.pool: Optional[ConnectionPool] = None
        self.initialized = False
        self._connection_lock = asyncio.Lock()
        
        # Redis key prefixes
        self.PREFIX_METRIC = "metric:"
        self.PREFIX_ALERT = "alert:"
        self.PREFIX_AGENT = "agent:"
        
        # TTLs (in seconds)
        self.DEFAULT_TTL = 60 * 60 * 24 * 7  # 7 days
        self.METRIC_TTL = int(config.options.get("metric_ttl_seconds", self.DEFAULT_TTL))
        self.ALERT_TTL = int(config.options.get("alert_ttl_seconds", self.DEFAULT_TTL * 2))
        self.AGENT_STATE_TTL = int(config.options.get("agent_state_ttl_seconds", 60 * 60))  # 1 hour
    
    async def connect(self):
        """Connect to Redis"""
        if self.initialized and self.redis:
            return
            
        async with self._connection_lock:
            if self.initialized and self.redis:
                return
                
            try:
                # Create connection pool
                self.pool = aioredis.ConnectionPool.from_url(
                    self.config.connection_string,
                    max_connections=10
                )
                
                # Create Redis client
                self.redis = Redis(connection_pool=self.pool)
                
                # Verify connection
                await self.redis.ping()
                self.initialized = True
                logger.info(f"Connected to Redis at {self.config.connection_string}")
                
            except Exception as e:
                logger.error(f"Failed to connect to Redis: {str(e)}")
                if self.redis:
                    await self.redis.close()
                    self.redis = None
                if self.pool:
                    await self.pool.disconnect()
                    self.pool = None
                raise
    
    async def close(self):
        """Close the Redis connection"""
        if self.redis:
            await self.redis.close()
            self.redis = None
            
        if self.pool:
            await self.pool.disconnect()
            self.pool = None
            
        self.initialized = False
        logger.info("Closed Redis connection")
    
    # Helper methods for Redis keys
    def _metric_key(self, metric_id: str) -> str:
        return f"{self.PREFIX_METRIC}{metric_id}"
    
    def _alert_key(self, alert_id: str) -> str:
        return f"{self.PREFIX_ALERT}{alert_id}"
    
    def _agent_key(self, agent_id: str) -> str:
        return f"{self.PREFIX_AGENT}{agent_id}"
    
    # Metric methods
    async def save_metric(self, metric: Metric) -> bool:
        try:
            metric_data = {
                'id': str(metric.id),
                'name': metric.name,
                'type': metric.type.value if hasattr(metric.type, 'value') else str(metric.type),
                'values': [
                    {
                        'timestamp': v.timestamp.isoformat(),
                        'value': v.value,
                        'tags': v.tags
                    }
                    for v in metric.values
                ],
                'metadata': metric.metadata or {},
                'created_at': metric.created_at.isoformat(),
                'updated_at': metric.updated_at.isoformat()
            }
            
            await self.redis.set(
                self._metric_key(str(metric.id)),
                json.dumps(metric_data),
                ex=self.METRIC_TTL
            )
            return True
            
        except Exception as e:
            logger.error(f"Error saving metric: {str(e)}", exc_info=True)
            return False
    
    async def get_metric(self, metric_id: str) -> Optional[Metric]:
        try:
            data = await self.redis.get(self._metric_key(metric_id))
            if not data:
                return None
                
            return self._metric_from_dict(json.loads(data))
            
        except Exception as e:
            logger.error(f"Error getting metric: {str(e)}", exc_info=True)
            return None
    
    # Alert methods
    async def save_alert(self, alert: Alert) -> bool:
        try:
            alert_data = {
                'id': str(alert.id),
                'name': alert.name,
                'description': alert.description,
                'severity': alert.severity.value if hasattr(alert.severity, 'value') else str(alert.severity),
                'status': alert.status,
                'source': alert.source,
                'start_time': alert.start_time.isoformat(),
                'end_time': alert.end_time.isoformat() if alert.end_time else None,
                'labels': alert.labels or {},
                'annotations': alert.annotations or {},
                'created_at': alert.created_at.isoformat(),
                'updated_at': alert.updated_at.isoformat()
            }
            
            await self.redis.set(
                self._alert_key(str(alert.id)),
                json.dumps(alert_data),
                ex=self.ALERT_TTL
            )
            return True
            
        except Exception as e:
            logger.error(f"Error saving alert: {str(e)}", exc_info=True)
            return False
    
    async def get_alert(self, alert_id: str) -> Optional[Alert]:
        try:
            data = await self.redis.get(self._alert_key(alert_id))
            if not data:
                return None
                
            return self._alert_from_dict(json.loads(data))
            
        except Exception as e:
            logger.error(f"Error getting alert: {str(e)}", exc_info=True)
            return None
    
    # Agent state methods
    async def save_agent_state(self, state: AgentState) -> bool:
        try:
            state_data = {
                'id': str(state.id),
                'agent_id': str(state.agent_id),
                'status': state.status,
                'metrics': state.metrics or {},
                'last_heartbeat': state.last_heartbeat.isoformat(),
                'created_at': state.created_at.isoformat(),
                'updated_at': state.updated_at.isoformat()
            }
            
            await self.redis.set(
                self._agent_key(str(state.agent_id)),
                json.dumps(state_data),
                ex=self.AGENT_STATE_TTL
            )
            return True
            
        except Exception as e:
            logger.error(f"Error saving agent state: {str(e)}", exc_info=True)
            return False
    
    async def get_agent_state(self, agent_id: str) -> Optional[AgentState]:
        try:
            data = await self.redis.get(self._agent_key(agent_id))
            if not data:
                return None
                
            return self._agent_state_from_dict(json.loads(data))
            
        except Exception as e:
            logger.error(f"Error getting agent state: {str(e)}", exc_info=True)
            return None
    
    # Query methods (simplified implementations)
    async def query_metrics(self, **kwargs) -> List[Metric]:
        # Implementation would scan keys and filter in memory
        # In production, use Redis search or external index
        return []
    
    async def query_alerts(self, **kwargs) -> List[Alert]:
        # Implementation would scan keys and filter in memory
        # In production, use Redis search or external index
        return []
    
    async def get_agent_states(self, **kwargs) -> List[AgentState]:
        # Implementation would scan keys and filter in memory
        # In production, use Redis search or external index
        return []
    
    # Helper methods to convert between dicts and model objects
    def _metric_from_dict(self, data: Dict[str, Any]) -> Metric:
        from ..data_models import MetricValue
        
        values = [
            MetricValue(
                timestamp=datetime.fromisoformat(v['timestamp']),
                value=v['value'],
                tags=v.get('tags', {})
            )
            for v in data['values']
        ]
        
        return Metric(
            id=data['id'],
            name=data['name'],
            type=data['type'],
            values=values,
            metadata=data.get('metadata', {}),
            created_at=datetime.fromisoformat(data['created_at']),
            updated_at=datetime.fromisoformat(data['updated_at'])
        )
    
    def _alert_from_dict(self, data: Dict[str, Any]) -> Alert:
        return Alert(
            id=data['id'],
            name=data['name'],
            description=data['description'],
            severity=data['severity'],
            status=data['status'],
            source=data['source'],
            start_time=datetime.fromisoformat(data['start_time']),
            end_time=datetime.fromisoformat(data['end_time']) if data.get('end_time') else None,
            labels=data.get('labels', {}),
            annotations=data.get('annotations', {}),
            created_at=datetime.fromisoformat(data['created_at']),
            updated_at=datetime.fromisoformat(data['updated_at'])
        )
    
    def _agent_state_from_dict(self, data: Dict[str, Any]) -> AgentState:
        return AgentState(
            id=data['id'],
            agent_id=data['agent_id'],
            status=data['status'],
            metrics=data.get('metrics', {}),
            last_heartbeat=datetime.fromisoformat(data['last_heartbeat']),
            created_at=datetime.fromisoformat(data['created_at']),
            updated_at=datetime.fromisoformat(data['updated_at'])
        )
    
    async def get_database_stats(self) -> Dict[str, Any]:
        try:
            info = await self.redis.info()
            return {
                'backend': 'Redis',
                'version': info.get('redis_version', 'unknown'),
                'uptime_seconds': info.get('uptime_in_seconds', 0),
                'connected_clients': info.get('connected_clients', 0),
                'used_memory': info.get('used_memory_human', 'N/A'),
                'total_commands_processed': info.get('total_commands_processed', 0)
            }
        except Exception as e:
            logger.error(f"Error getting Redis stats: {str(e)}", exc_info=True)
            return {'error': str(e)}
