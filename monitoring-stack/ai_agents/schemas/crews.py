from datetime import datetime
from typing import Dict, List, Optional, Set, Any
from uuid import UUID, uuid4
from pydantic import Field, validator, root_validator, HttpUrl
from .base import BaseModelWithConfig, AgentType, AgentStatus
from .agents import AgentCapabilities, AgentResources

class CrewRole(BaseModelWithConfig):
    """Definition of a role within a crew"""
    role_id: UUID = Field(default_factory=uuid4)
    name: str
    description: str = ""
    required_agent_types: List[AgentType] = Field(default_factory=list)
    min_agents: int = 1
    max_agents: Optional[int] = None
    capabilities: AgentCapabilities = Field(default_factory=AgentCapabilities)
    resources: AgentResources = Field(default_factory=AgentResources)
    is_lead_role: bool = False
    can_escalate: bool = False
    can_delegate: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

class CrewMember(BaseModelWithConfig):
    """An agent assigned to a crew role"""
    agent_id: UUID
    role_id: UUID
    join_date: datetime = Field(default_factory=datetime.utcnow)
    is_active: bool = True
    permissions: Dict[str, List[str]] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)

class CrewPolicy(BaseModelWithConfig):
    """Policies governing crew behavior"""
    max_concurrent_tasks: int = 10
    task_timeout_seconds: int = 3600
    retry_attempts: int = 3
    escalation_path: List[UUID] = Field(default_factory=list)
    notification_channels: List[str] = Field(default_factory=list)
    approval_required: bool = False
    audit_logging: bool = True
    data_retention_days: int = 90
    backup_enabled: bool = True
    backup_retention_days: int = 365

class CrewMetrics(BaseModelWithConfig):
    """Metrics for crew performance"""
    total_tasks_completed: int = 0
    total_tasks_failed: int = 0
    average_task_duration_seconds: float = 0.0
    active_task_count: int = 0
    member_count: int = 0
    last_activity: Optional[datetime] = None
    uptime_percentage: float = 100.0
    error_rate: float = 0.0

class CrewDefinition(BaseModelWithConfig):
    """Complete definition of a crew"""
    crew_id: UUID = Field(default_factory=uuid4)
    name: str
    description: str = ""
    purpose: str = ""
    created_by: UUID
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    is_active: bool = True
    tags: List[str] = Field(default_factory=list)
    version: str = "1.0.0"
    
    # Crew composition
    roles: Dict[UUID, CrewRole] = Field(default_factory=dict)
    members: Dict[UUID, CrewMember] = Field(default_factory=dict)
    
    # Configuration
    policy: CrewPolicy = Field(default_factory=CrewPolicy)
    metrics: CrewMetrics = Field(default_factory=CrewMetrics)
    
    # Relationships
    parent_crew_id: Optional[UUID] = None
    child_crew_ids: List[UUID] = Field(default_factory=list)
    
    @root_validator
    def validate_crew(cls, values):
        # Ensure at least one role is defined as lead
        roles = values.get('roles', {})
        has_lead = any(role.is_lead_role for role in roles.values())
        if not has_lead and roles:
            # Automatically set the first role as lead if none is defined
            first_role_id = next(iter(roles))
            roles[first_role_id].is_lead_role = True
        
        # Update timestamp
        values['updated_at'] = datetime.utcnow()
        return values
    
    def add_role(self, role: CrewRole) -> UUID:
        """Add a new role to the crew"""
        if not any(r.name.lower() == role.name.lower() for r in self.roles.values()):
            self.roles[role.role_id] = role
            return role.role_id
        raise ValueError(f"Role with name '{role.name}' already exists in crew")
    
    def add_member(self, agent_id: UUID, role_id: UUID, **kwargs) -> UUID:
        """Add a member to the crew"""
        if role_id not in self.roles:
            raise ValueError(f"Role ID {role_id} does not exist in this crew")
        
        # Check if agent is already in this role
        for member in self.members.values():
            if member.agent_id == agent_id and member.role_id == role_id and member.is_active:
                raise ValueError(f"Agent {agent_id} is already a member of role {role_id}")
        
        # Create new member
        member_id = uuid4()
        self.members[member_id] = CrewMember(
            agent_id=agent_id,
            role_id=role_id,
            **kwargs
        )
        return member_id
    
    def get_members_by_role(self, role_id: UUID) -> List[CrewMember]:
        """Get all members of a specific role"""
        return [m for m in self.members.values() if m.role_id == role_id and m.is_active]
    
    def get_lead_members(self) -> List[CrewMember]:
        """Get all members with lead roles"""
        lead_roles = [r.role_id for r in self.roles.values() if r.is_lead_role]
        return [m for m in self.members.values() if m.role_id in lead_roles and m.is_active]

class CrewRegistration(BaseModelWithConfig):
    """Registration request for a new crew"""
    name: str
    description: str = ""
    purpose: str = ""
    created_by: UUID
    roles: List[Dict[str, Any]] = Field(default_factory=list)
    policy: Optional[Dict[str, Any]] = None
    parent_crew_id: Optional[UUID] = None

class CrewUpdate(BaseModelWithConfig):
    """Update request for an existing crew"""
    name: Optional[str] = None
    description: Optional[str] = None
    purpose: Optional[str] = None
    is_active: Optional[bool] = None
    policy: Optional[Dict[str, Any]] = None
    metadata: Optional[Dict[str, Any]] = None

class CrewMembershipRequest(BaseModelWithConfig):
    """Request to add/update crew membership"""
    agent_id: UUID
    role_id: UUID
    permissions: Optional[Dict[str, List[str]]] = None
    metadata: Optional[Dict[str, Any]] = None

class CrewTaskAssignment(BaseModelWithConfig):
    """Assignment of a task to a crew"""
    task_id: UUID
    crew_id: UUID
    assigned_by: UUID
    assigned_at: datetime = Field(default_factory=datetime.utcnow)
    deadline: Optional[datetime] = None
    priority: int = 2  # 1=low, 2=normal, 3=high, 4=critical
    requirements: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)
