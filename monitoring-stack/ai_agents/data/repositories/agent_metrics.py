"""Repository for AgentMetrics operations."""
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Union
from uuid import UUID

from ..models import AgentMetrics
from .base_repository import BaseRepository

class AgentMetricsRepository(BaseRepository[AgentMetrics]):
    """Repository for AgentMetrics time-series operations."""
    
    def __init__(self):
        """Initialize the repository with the table name and model class."""
        super().__init__("agent_metrics", AgentMetrics)
    
    async def get_metrics_by_agent(
        self, 
        agent_id: UUID,
        metric_name: Optional[str] = None,
        start_time: Optional[datetime] = None,
        end_time: Optional[datetime] = None,
        limit: int = 1000
    ) -> List[AgentMetrics]:
        """Get metrics for a specific agent with optional filters."""
        query = {"agent_id": str(agent_id)}
        
        if metric_name:
            query["name"] = metric_name
            
        if start_time or end_time:
            time_filter = {}
            if start_time:
                time_filter["gte"] = start_time.isoformat()
            if end_time:
                time_filter["lte"] = end_time.isoformat()
            query["timestamp"] = time_filter
        
        # Order by most recent first
        result = await self._execute_query(
            get_supabase_client()
            .table(self.table_name)
            .select("*")
            .match(query)
            .order("timestamp", desc=True)
            .limit(limit)
        )
        
        return [self.model_class(**item) for item in result.data]
    
    async def record_metric(self, metric: AgentMetrics) -> AgentMetrics:
        """Record a new metric value."""
        return await self.create(metric.dict())
    
    async def get_metric_stats(
        self,
        metric_name: str,
        time_window: timedelta = timedelta(hours=1),
        group_interval: timedelta = timedelta(minutes=5)
    ) -> List[Dict[str, Union[datetime, float]]]:
        """Get aggregated statistics for a metric over time."""
        end_time = datetime.utcnow()
        start_time = end_time - time_window
        
        # This is a simplified example - in a real app, you'd use Supabase's RPC
        # for time-series aggregation
        query = f"""
        SELECT 
            time_bucket_gapfill(
                '{interval} seconds', 
                timestamp, 
                start => '{start_time.isoformat()}', 
                finish => '{end_time.isoformat()}'
            ) as bucket,
            avg(value) as avg_value,
            min(value) as min_value,
            max(value) as max_value,
            count(*) as sample_count
        FROM {self.table_name}
        WHERE 
            name = '{metric_name}'
            AND timestamp >= '{start_time.isoformat()}'
            AND timestamp <= '{end_time.isoformat()}'
        GROUP BY bucket
        ORDER BY bucket
        """.format(
            interval=group_interval.total_seconds(),
            start_time=start_time.isoformat(),
            end_time=end_time.isoformat(),
            table_name=self.table_name,
            metric_name=metric_name
        )
        
        result = await self._execute_rpc(query)
        return result.data if result else []
    
    async def get_latest_metric(
        self, 
        agent_id: UUID, 
        metric_name: str
    ) -> Optional[AgentMetrics]:
        """Get the most recent value for a specific metric."""
        result = await self._execute_query(
            get_supabase_client()
            .table(self.table_name)
            .select("*")
            .match({"agent_id": str(agent_id), "name": metric_name})
            .order("timestamp", desc=True)
            .limit(1)
        )
        
        return self.model_class(**result.data[0]) if result.data else None
