from datetime import datetime
from typing import Dict, List, Optional, Set, Any, Union
from uuid import UUID, uuid4
from pydantic import Field, validator, root_validator, HttpUrl
from .base import BaseModelWithConfig, AgentType, AgentStatus, AgentCapability

class AgentCapabilities(BaseModelWithConfig):
    """Defines what an agent can do"""
    read: bool = False
    write: bool = False
    execute: bool = False
    monitor: bool = False
    alert: bool = False
    heal: bool = False
    backup: bool = False
    restore: bool = False
    deploy: bool = False
    test: bool = False
    validate: bool = False
    notify: bool = False
    analyze: bool = False
    optimize: bool = False
    secure: bool = False
    audit: bool = False

class AgentResources(BaseModelWithConfig):
    """Resource constraints for an agent"""
    max_cpu_percent: float = 80.0
    max_memory_mb: int = 1024
    max_disk_mb: int = 100
    max_network_mbps: float = 10.0
    max_concurrent_tasks: int = 10

class AgentMetrics(BaseModelWithConfig):
    """Runtime metrics for an agent"""
    cpu_usage: float = 0.0
    memory_usage_mb: float = 0.0
    disk_usage_mb: float = 0.0
    network_usage_mbps: float = 0.0
    active_tasks: int = 0
    total_tasks_processed: int = 0
    error_count: int = 0
    last_heartbeat: Optional[datetime] = None
    uptime_seconds: float = 0.0

class AgentConfig(BaseModelWithConfig):
    """Configuration for an agent"""
    log_level: str = "INFO"  # DEBUG, INFO, WARNING, ERROR, CRITICAL
    max_retry_attempts: int = 3
    retry_delay_seconds: int = 5
    heartbeat_interval_seconds: int = 30
    log_retention_days: int = 30
    data_retention_days: int = 90
    backup_enabled: bool = True
    backup_interval_hours: int = 24
    alert_on_errors: bool = True
    alert_on_warnings: bool = False

class AgentDependencies(BaseModelWithConfig):
    """External services and resources this agent depends on"""
    required_services: List[str] = Field(default_factory=list)
    required_apis: List[str] = Field(default_factory=list)
    required_libraries: List[str] = Field(default_factory=list)
    required_credentials: List[str] = Field(default_factory=list)
    required_network_ports: List[int] = Field(default_factory=list)
    required_storage_paths: List[str] = Field(default_factory=list)

class AgentIdentity(BaseModelWithConfig):
    """Identification information for an agent"""
    agent_id: UUID = Field(default_factory=uuid4)
    name: str
    alias: Optional[str] = None
    description: str = ""
    version: str = "1.0.0"
    agent_type: AgentType
    tags: List[str] = Field(default_factory=list)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    owner: Optional[str] = None
    contact_email: Optional[str] = None
    documentation_url: Optional[HttpUrl] = None

class AgentState(BaseModelWithConfig):
    """Runtime state of an agent"""
    status: AgentStatus = AgentStatus.STARTING
    last_active: Optional[datetime] = None
    last_error: Optional[str] = None
    current_task: Optional[str] = None
    task_start_time: Optional[datetime] = None
    task_progress: float = 0.0
    metadata: Dict[str, Any] = Field(default_factory=dict)
    metrics: AgentMetrics = Field(default_factory=AgentMetrics)

class AgentDefinition(BaseModelWithConfig):
    """Complete definition of an AI agent"""
    identity: AgentIdentity
    capabilities: AgentCapabilities = Field(default_factory=AgentCapabilities)
    resources: AgentResources = Field(default_factory=AgentResources)
    config: AgentConfig = Field(default_factory=AgentConfig)
    dependencies: AgentDependencies = Field(default_factory=AgentDependencies)
    state: AgentState = Field(default_factory=AgentState)
    
    @root_validator
    def validate_agent(cls, values):
        """Validate agent configuration"""
        identity = values.get('identity')
        capabilities = values.get('capabilities')
        
        # Ensure agent has at least one capability
        if not any(capabilities.dict().values()):
            raise ValueError("Agent must have at least one capability enabled")
            
        # Update the updated_at timestamp
        if identity:
            values['identity'].updated_at = datetime.utcnow()
            
        return values
    
    def to_dict(self, include_state: bool = True) -> Dict[str, Any]:
        """Convert agent to dictionary, optionally excluding state"""
        data = self.dict()
        if not include_state:
            data.pop('state', None)
        return data

class AgentRegistration(BaseModelWithConfig):
    """Registration request for a new agent"""
    name: str
    agent_type: AgentType
    capabilities: AgentCapabilities
    config: Optional[AgentConfig] = None
    dependencies: Optional[AgentDependencies] = None

class AgentUpdate(BaseModelWithConfig):
    """Update request for an existing agent"""
    status: Optional[AgentStatus] = None
    config: Optional[Dict[str, Any]] = None
    capabilities: Optional[Dict[str, bool]] = None
    metadata: Optional[Dict[str, Any]] = None
    
    @validator('config')
    def validate_config(cls, v):
        if v is not None:
            # Validate config against AgentConfig model
            AgentConfig(**v)
        return v

class AgentHeartbeat(BaseModelWithConfig):
    """Heartbeat message from an agent"""
    agent_id: UUID
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    status: AgentStatus
    metrics: Optional[AgentMetrics] = None
    current_task: Optional[str] = None
    task_progress: float = 0.0
