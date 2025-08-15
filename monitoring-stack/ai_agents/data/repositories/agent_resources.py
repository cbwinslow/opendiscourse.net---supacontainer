"""Repository for AgentResources operations."""
from typing import Dict, List, Optional, Tuple
from uuid import UUID

from ..models import AgentResources
from .base_repository import BaseRepository

class AgentResourcesRepository(BaseRepository[AgentResources]):
    """Repository for AgentResources CRUD operations."""
    
    def __init__(self):
        """Initialize the repository with the table name and model class."""
        super().__init__("agent_resources", AgentResources)
    
    async def get_by_name(self, name: str) -> Optional[AgentResources]:
        """Get a resource by name."""
        result = await self.query({"name": name})
        return result[0] if result else None
    
    async def get_available_resources(self) -> List[AgentResources]:
        """Get all available resources."""
        return await self.query({"is_available": True})
    
    async def get_resources_by_type(self, resource_type: str) -> List[AgentResources]:
        """Get resources by type."""
        return await self.query({"type": resource_type})
    
    async def get_resource_utilization(self) -> Dict[str, Tuple[float, float]]:
        """Get resource utilization across all resources.
        
        Returns:
            Dict mapping resource type to (used, total) tuple
        """
        resources = await self.get_all()
        utilization = {}
        
        for resource in resources:
            if resource.type not in utilization:
                utilization[resource.type] = [0.0, 0.0]
                
            if resource.is_available:
                utilization[resource.type][1] += resource.capacity
            else:
                utilization[resource.type][0] += resource.capacity
        
        return {k: tuple(v) for k, v in utilization.items()}
