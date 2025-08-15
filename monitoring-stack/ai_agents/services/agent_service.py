"""Service layer for agent-related operations."""
from typing import Dict, List, Optional, Tuple, Union
from uuid import UUID
from datetime import datetime, timedelta

from ..data.models import AgentCapabilities, AgentResources, AgentMetrics
from ..data.repositories import (
    AgentCapabilitiesRepository,
    AgentResourcesRepository,
    AgentMetricsRepository
)

class AgentService:
    """Service for agent-related operations."""
    
    def __init__(self):
        """Initialize the service with repository instances."""
        self.capabilities_repo = AgentCapabilitiesRepository()
        self.resources_repo = AgentResourcesRepository()
        self.metrics_repo = AgentMetricsRepository()
    
    # Agent Capabilities Methods
    
    async def get_capability(self, capability_id: UUID) -> Optional[AgentCapabilities]:
        """Get a capability by ID."""
        return await self.capabilities_repo.get_by_id(capability_id)
    
    async def create_capability(self, name: str, description: str = None, 
                              parameters: Dict = None) -> AgentCapabilities:
        """Create a new capability."""
        capability = AgentCapabilities(
            name=name,
            description=description,
            parameters=parameters or {}
        )
        return await self.capabilities_repo.create(capability.dict())
    
    # Agent Resources Methods
    
    async def register_resource(
        self,
        name: str,
        resource_type: str,
        capacity: float,
        unit: str,
        description: str = None
    ) -> AgentResources:
        """Register a new agent resource."""
        resource = AgentResources(
            name=name,
            type=resource_type,
            capacity=capacity,
            unit=unit,
            description=description,
            is_available=True
        )
        return await self.resources_repo.create(resource.dict())
    
    async def get_resource_utilization(self) -> Dict[str, Dict[str, float]]:
        """Get resource utilization across all resource types."""
        utilization = await self.resources_repo.get_resource_utilization()
        return {
            resource_type: {
                "used": used,
                "total": total,
                "utilization": (used / total) * 100 if total > 0 else 0.0
            }
            for resource_type, (used, total) in utilization.items()
        }
    
    # Agent Metrics Methods
    
    async def record_metric(
        self,
        agent_id: UUID,
        name: str,
        value: float,
        tags: Dict[str, str] = None
    ) -> AgentMetrics:
        """Record a new metric value."""
        metric = AgentMetrics(
            agent_id=agent_id,
            name=name,
            value=value,
            tags=tags or {}
        )
        return await self.metrics_repo.record_metric(metric)
    
    async def get_metric_history(
        self,
        agent_id: UUID,
        metric_name: str,
        time_window: timedelta = timedelta(hours=24),
        limit: int = 1000
    ) -> List[AgentMetrics]:
        """Get historical metric data for an agent."""
        end_time = datetime.utcnow()
        start_time = end_time - time_window
        
        return await self.metrics_repo.get_metrics_by_agent(
            agent_id=agent_id,
            metric_name=metric_name,
            start_time=start_time,
            end_time=end_time,
            limit=limit
        )
    
    async def get_agent_health(
        self,
        agent_id: UUID,
        time_window: timedelta = timedelta(minutes=5)
    ) -> Dict[str, Union[bool, Dict]]:
        """Get health status for an agent based on recent metrics."""
        metrics = await self.get_metric_history(
            agent_id=agent_id,
            time_window=time_window
        )
        
        # This is a simplified health check - in a real app, you'd have more sophisticated logic
        health_status = {
            "agent_id": agent_id,
            "is_healthy": True,
            "last_seen": None,
            "metrics": {}
        }
        
        if metrics:
            health_status["last_seen"] = max(m.timestamp for m in metrics)
            
            # Check if we've seen the agent recently
            time_since_last_metric = datetime.utcnow() - health_status["last_seen"]
            if time_since_last_metric > time_window * 2:
                health_status["is_healthy"] = False
                health_status["reason"] = "No recent metrics"
        else:
            health_status["is_healthy"] = False
            health_status["reason"] = "No metrics found"
        
        return health_status
