from abc import ABC, abstractmethod
from typing import Dict, Any, List, Optional, Union
from datetime import datetime, timedelta

from ..data_models import (
    Metric, Alert, AgentState, QueryOptions, QueryFilter,
    StorageConfig, StorageBackendType
)

class BaseStorageBackend(ABC):
    """Abstract base class for storage backends"""
    
    def __init__(self, config: StorageConfig):
        """Initialize the storage backend"""
        self.config = config
    
    @abstractmethod
    async def connect(self):
        """Connect to the storage backend"""
        pass
    
    @abstractmethod
    async def close(self):
        """Close the connection to the storage backend"""
        pass
    
    # Metric methods
    @abstractmethod
    async def save_metric(self, metric: Metric) -> bool:
        """Save a metric to the storage backend"""
        pass
    
    @abstractmethod
    async def get_metric(self, metric_id: str) -> Optional[Metric]:
        """Get a metric by ID"""
        pass
    
    @abstractmethod
    async def query_metrics(
        self,
        name: str = None,
        metric_type: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        tags: Dict[str, str] = None,
        options: QueryOptions = None
    ) -> List[Metric]:
        """Query metrics with filters"""
        pass
    
    # Alert methods
    @abstractmethod
    async def save_alert(self, alert: Alert) -> bool:
        """Save an alert to the storage backend"""
        pass
    
    @abstractmethod
    async def get_alert(self, alert_id: str) -> Optional[Alert]:
        """Get an alert by ID"""
        pass
    
    @abstractmethod
    async def query_alerts(
        self,
        status: str = None,
        severity: str = None,
        source: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        labels: Dict[str, str] = None,
        options: QueryOptions = None
    ) -> List[Alert]:
        """Query alerts with filters"""
        pass
    
    # Agent state methods
    @abstractmethod
    async def save_agent_state(self, state: AgentState) -> bool:
        """Save an agent state to the storage backend"""
        pass
    
    @abstractmethod
    async def get_agent_state(self, agent_id: str) -> Optional[AgentState]:
        """Get the latest state for an agent"""
        pass
    
    @abstractmethod
    async def get_agent_states(
        self,
        status: str = None,
        last_heartbeat_after: datetime = None,
        options: QueryOptions = None
    ) -> List[AgentState]:
        """Query agent states with filters"""
        pass
    
    # Optional methods with default implementations
    async def get_metric_history(
        self,
        metric_name: str,
        start_time: datetime = None,
        end_time: datetime = None,
        step: timedelta = None,
        aggregation: str = "avg"
    ) -> List[Dict[str, Any]]:
        """
        Get historical metric data with optional downsampling.
        
        Args:
            metric_name: Name of the metric to query
            start_time: Start time for the query
            end_time: End time for the query
            step: Time interval for downsampling
            aggregation: Aggregation function (avg, sum, min, max, count)
            
        Returns:
            List of metric values with timestamps
        """
        # Default implementation uses query_metrics and performs in-memory aggregation
        metrics = await self.query_metrics(
            name=metric_name,
            start_time=start_time,
            end_time=end_time
        )
        
        if not metrics:
            return []
            
        # Extract all values
        values = []
        for metric in metrics:
            for value in metric.values:
                if start_time and value.timestamp < start_time:
                    continue
                if end_time and value.timestamp > end_time:
                    continue
                values.append({
                    'timestamp': value.timestamp,
                    'value': value.value,
                    'tags': value.tags
                })
        
        # Sort by timestamp
        values.sort(key=lambda x: x['timestamp'])
        
        # Apply downsampling if step is specified
        if step and len(values) > 1:
            return self._downsample_metrics(values, step, aggregation)
        
        return values
    
    def _downsample_metrics(
        self, 
        values: List[Dict[str, Any]], 
        step: timedelta, 
        aggregation: str = "avg"
    ) -> List[Dict[str, Any]]:
        """Downsample metrics by aggregating within time windows"""
        if not values:
            return []
            
        # Sort values by timestamp
        values.sort(key=lambda x: x['timestamp'])
        
        # Determine time windows
        start_time = values[0]['timestamp']
        end_time = values[-1]['timestamp']
        
        # Create time windows
        current_window_start = start_time
        windows = []
        
        while current_window_start < end_time:
            window_end = current_window_start + step
            windows.append({
                'start': current_window_start,
                'end': window_end,
                'values': []
            })
            current_window_start = window_end
        
        # Assign values to windows
        for value in values:
            # Find the appropriate window
            for window in windows:
                if window['start'] <= value['timestamp'] < window['end']:
                    window['values'].append(value['value'])
                    break
        
        # Apply aggregation to each window
        result = []
        for window in windows:
            if not window['values']:
                continue
                
            if aggregation == 'avg':
                value = sum(window['values']) / len(window['values'])
            elif aggregation == 'sum':
                value = sum(window['values'])
            elif aggregation == 'min':
                value = min(window['values'])
            elif aggregation == 'max':
                value = max(window['values'])
            elif aggregation == 'count':
                value = len(window['values'])
            else:
                value = sum(window['values']) / len(window['values'])  # Default to avg
            
            result.append({
                'timestamp': window['start'],
                'value': value,
                'count': len(window['values'])
            })
        
        return result
    
    async def backup_database(self, backup_path: str) -> bool:
        """
        Create a backup of the database.
        
        Args:
            backup_path: Path to save the backup file
            
        Returns:
            bool: True if backup was successful, False otherwise
        """
        raise NotImplementedError("Backup not implemented for this backend")
    
    async def restore_database(self, backup_path: str) -> bool:
        """
        Restore the database from a backup.
        
        Args:
            backup_path: Path to the backup file
            
        Returns:
            bool: True if restore was successful, False otherwise
        """
        raise NotImplementedError("Restore not implemented for this backend")
    
    async def get_database_stats(self) -> Dict[str, Any]:
        """
        Get database statistics.
        
        Returns:
            Dict containing database statistics
        """
        return {
            'backend': self.__class__.__name__,
            'supports_backup': hasattr(self, 'backup_database') and callable(self.backup_database),
            'supports_restore': hasattr(self, 'restore_database') and callable(self.restore_database)
        }
