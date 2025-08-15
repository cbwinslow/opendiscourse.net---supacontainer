"""Base repository class for Supabase operations."""
from typing import Any, Dict, Generic, List, Optional, Type, TypeVar
from uuid import UUID
import logging

from ..models import BaseModel
from .config import get_supabase_client

T = TypeVar('T', bound=BaseModel)

class BaseRepository(Generic[T]):
    """Base repository for Supabase CRUD operations."""
    
    def __init__(self, table_name: str, model_class: Type[T]):
        """Initialize the repository.
        
        Args:
            table_name: Name of the Supabase table
            model_class: Model class for deserialization
        """
        self.table_name = table_name
        self.model_class = model_class
        self.logger = logging.getLogger(f"supabase.{table_name}")
    
    async def _execute_query(self, query_func, *args, **kwargs) -> Any:
        """Execute a Supabase query with error handling."""
        try:
            # In a real async context, you'd use an async Supabase client
            # For now, we'll assume the client is synchronous
            return query_func(*args, **kwargs).execute()
        except Exception as e:
            self.logger.error(f"Error executing query: {str(e)}", exc_info=True)
            raise
    
    async def get_by_id(self, id: UUID) -> Optional[T]:
        """Get a single record by ID."""
        result = await self._execute_query(
            get_supabase_client().table(self.table_name).select("*").eq("id", str(id))
        )
        if not result.data:
            return None
        return self.model_class(**result.data[0])
    
    async def get_all(self, limit: int = 100, offset: int = 0) -> List[T]:
        """Get all records with pagination."""
        result = await self._execute_query(
            get_supabase_client()
            .table(self.table_name)
            .select("*")
            .range(offset, offset + limit - 1)
        )
        return [self.model_class(**item) for item in result.data]
    
    async def create(self, data: Dict[str, Any]) -> T:
        """Create a new record."""
        result = await self._execute_query(
            get_supabase_client().table(self.table_name).insert([data])
        )
        if not result.data:
            raise ValueError("Failed to create record")
        return self.model_class(**result.data[0])
    
    async def update(self, id: UUID, data: Dict[str, Any]) -> Optional[T]:
        """Update an existing record."""
        result = await self._execute_query(
            get_supabase_client()
            .table(self.table_name)
            .update(data)
            .eq("id", str(id))
        )
        if not result.data:
            return None
        return self.model_class(**result.data[0])
    
    async def delete(self, id: UUID) -> bool:
        """Delete a record by ID."""
        result = await self._execute_query(
            get_supabase_client()
            .table(self.table_name)
            .delete()
            .eq("id", str(id))
        )
        return len(result.data) > 0
    
    async def query(self, filters: Dict[str, Any]) -> List[T]:
        """Query records with filters."""
        query = get_supabase_client().table(self.table_name).select("*")
        
        # Apply filters
        for key, value in filters.items():
            if isinstance(value, (list, tuple)):
                query = query.in_(key, value)
            else:
                query = query.eq(key, value)
        
        result = await self._execute_query(query)
        return [self.model_class(**item) for item in result.data]
