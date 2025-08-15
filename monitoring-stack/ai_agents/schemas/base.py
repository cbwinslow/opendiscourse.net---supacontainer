from enum import Enum, auto
from typing import Dict, List, Optional, Union, Any
from datetime import datetime
from pydantic import BaseModel, Field, validator, root_validator
from uuid import uuid4, UUID

class AgentType(str, Enum):
    ORCHESTRATOR = "orchestrator"
    TEAM_LEADER = "team_leader"
    SCRIBE = "scribe"
    NOTARY = "notary"
    ORGANIZER = "organizer"
    NETWORK_ENGINEER = "network_engineer"
    FILESYSTEM_ENGINEER = "filesystem_engineer"
    INSTRUCTION_SPECIALIST = "instruction_specialist"
    TROUBLESHOOTER = "troubleshooter"
    FIXER = "fixer"
    DOER = "doer"
    GRUNT = "grunt"
    MESSENGER = "messenger"
    CLEANER = "cleaner"
    TESTER = "tester"
    ANTIVIRUS = "antivirus"
    SELF_HEALING = "self_healing"
    MONITORING = "monitoring"
    BACKUP = "backup"
    DEPLOYMENT = "deployment"
    SECURITY = "security"
    AUDIT = "audit"

class MessageType(str, Enum):
    COMMAND = "command"
    RESPONSE = "response"
    BROADCAST = "broadcast"
    ALERT = "alert"
    LOG = "log"
    METRIC = "metric"
    STATUS_UPDATE = "status_update"
    TASK_REQUEST = "task_request"
    TASK_UPDATE = "task_update"
    TASK_COMPLETE = "task_complete"
    ERROR = "error"

class MessagePriority(int, Enum):
    LOW = 1
    NORMAL = 2
    HIGH = 3
    CRITICAL = 4

class AgentCapability(str, Enum):
    READ = "read"
    WRITE = "write"
    EXECUTE = "execute"
    MONITOR = "monitor"
    ALERT = "alert"
    HEAL = "heal"
    BACKUP = "backup"
    RESTORE = "restore"
    DEPLOY = "deploy"
    TEST = "test"
    VALIDATE = "validate"
    NOTIFY = "notify"
    ANALYZE = "analyze"
    OPTIMIZE = "optimize"
    SECURE = "secure"
    AUDIT = "audit"

class AgentStatus(str, Enum):
    STARTING = "starting"
    IDLE = "idle"
    BUSY = "busy"
    ERROR = "error"
    UPDATING = "updating"
    MAINTENANCE = "maintenance"
    TERMINATED = "terminated"

class BaseModelWithConfig(BaseModel):
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat(),
            UUID: lambda v: str(v),
        }
        use_enum_values = True
        validate_assignment = True
        extra = "forbid"  # Don't allow extra fields
        allow_population_by_field_name = True
