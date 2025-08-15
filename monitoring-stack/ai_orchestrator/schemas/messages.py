from enum import Enum
from typing import Dict, Any, List, Optional
from pydantic import BaseModel, Field, HttpUrl
from datetime import datetime

class MessageType(str, Enum):
    METRIC = "metric"
    LOG = "log"
    ALERT = "alert"
    COMMAND = "command"
    RESPONSE = "response"n
class Severity(str, Enum):
    DEBUG = "debug"
    INFO = "info"
    WARNING = "warning"
    ERROR = "error"
    CRITICAL = "critical"

class BaseMessage(BaseModel):
    message_type: MessageType
    source: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    content: Dict[str, Any]
    severity: Severity = Severity.INFO
    correlation_id: Optional[str] = None

class MetricMessage(BaseMessage):
    message_type: MessageType = MessageType.METRIC
    metric_name: str
    value: float
    tags: Dict[str, str] = {}

class LogMessage(BaseMessage):
    message_type: MessageType = MessageType.LOG
    message: str
    stack_trace: Optional[str] = None
    context: Dict[str, Any] = {}

class AlertMessage(BaseMessage):
    message_type: MessageType = MessageType.ALERT
    alert_name: str
    condition: str
    threshold: float
    current_value: float
    duration: str
    labels: Dict[str, str] = {}
    annotations: Dict[str, str] = {}

class CommandType(str, Enum):
    DEPLOY_AGENT = "deploy_agent"
    REMOVE_AGENT = "remove_agent"
    SCALE_SERVICE = "scale_service"
    EXECUTE_SCRIPT = "execute_script"
    RUN_HEALTH_CHECK = "run_health_check"

class CommandMessage(BaseMessage):
    message_type: MessageType = MessageType.COMMAND
    command: CommandType
    parameters: Dict[str, Any] = {}
    ttl_seconds: int = 300  # Time to live in seconds

class ResponseStatus(str, Enum):
    SUCCESS = "success"
    ERROR = "error"
    PENDING = "pending"
    TIMEOUT = "timeout"

class ResponseMessage(BaseMessage):
    message_type: MessageType = MessageType.RESPONSE
    status: ResponseStatus
    request_id: str
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None
