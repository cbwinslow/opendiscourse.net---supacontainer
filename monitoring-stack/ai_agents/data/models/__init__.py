"""Data models for the monitoring system."""
from uuid import UUID, uuid4
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime

class BaseModel(BaseModel):
    """Base model with common fields and methods."""
    id: UUID = Field(default_factory=uuid4)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    
    class Config:
        json_encoders = {
            UUID: lambda v: str(v),
            datetime: lambda v: v.isoformat()
        }
        orm_mode = True

class AgentCapabilities(BaseModel):
    """Model for agent capabilities."""
    name: str
    description: Optional[str] = None
    parameters: Optional[Dict[str, Any]] = None
    is_active: bool = True

class AgentResources(BaseModel):
    """Model for agent resources."""
    name: str
    description: Optional[str] = None
    type: str  # e.g., "cpu", "gpu", "memory"
    capacity: float
    unit: str  # e.g., "cores", "GB"
    is_available: bool = True

class AgentMetrics(BaseModel):
    """Model for agent metrics."""
    agent_id: UUID
    name: str
    value: float
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    tags: Optional[Dict[str, str]] = None
    
    class Config:
        json_encoders = {
            UUID: lambda v: str(v),
            datetime: lambda v: v.isoformat()
        }

# Add any additional models or relationships here
