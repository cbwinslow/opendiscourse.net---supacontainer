"""Repository for AgentCapabilities operations."""
from typing import Dict, List, Optional
from uuid import UUID

from ..models import AgentCapabilities
from .base_repository import BaseRepository

class AgentCapabilitiesRepository(BaseRepository[AgentCapabilities]):
    """Repository for AgentCapabilities CRUD operations."""
    
    def __init__(self):
        """Initialize the repository with the table name and model class."""
        super().__init__("agent_capabilities", AgentCapabilities)
    
    async def get_by_name(self, name: str) -> Optional[AgentCapabilities]:
        """Get a capability by name."""
        result = await self.query({"name": name})
        return result[0] if result else None
    
    async def get_active_capabilities(self) -> List[AgentCapabilities]:
        """Get all active capabilities."""
        return await self.query({"is_active": True})
    
    async def search(self, query: str) -> List[AgentCapabilities]:
        """Search capabilities by name or description."""
        # This is a simplified search - in a real app, you'd use Supabase's full-text search
        return await self.query({"name": {"ilike": f"%{query}%"}})
