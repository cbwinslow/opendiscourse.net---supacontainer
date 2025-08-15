from datetime import datetime
from typing import Dict, List, Optional, Any, Union
from uuid import UUID, uuid4
from pydantic import Field, validator, root_validator
from .base import BaseModelWithConfig, MessageType, MessagePriority, AgentType

class MessageHeader(BaseModelWithConfig):
    message_id: UUID = Field(default_factory=uuid4)
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    message_type: MessageType
    priority: MessagePriority = MessagePriority.NORMAL
    source_agent_id: UUID
    target_agent_ids: List[UUID] = Field(default_factory=list)
    is_broadcast: bool = False
    correlation_id: Optional[UUID] = None
    parent_message_id: Optional[UUID] = None
    requires_ack: bool = True
    ttl_seconds: Optional[int] = 3600  # Time to live in seconds

class MessagePayload(BaseModelWithConfig):
    content: Dict[str, Any] = Field(default_factory=dict)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    attachments: List[Dict[str, Any]] = Field(default_factory=list)

class Message(BaseModelWithConfig):
    header: MessageHeader
    payload: MessagePayload
    
    def to_log_dict(self) -> Dict[str, Any]:
        """Convert message to a dictionary suitable for logging"""
        return {
            "message_id": str(self.header.message_id),
            "timestamp": self.header.timestamp.isoformat(),
            "message_type": self.header.message_type,
            "source_agent_id": str(self.header.source_agent_id),
            "target_agent_ids": [str(agent_id) for agent_id in self.header.target_agent_ids],
            "is_broadcast": self.header.is_broadcast,
            "correlation_id": str(self.header.correlation_id) if self.header.correlation_id else None,
            "parent_message_id": str(self.header.parent_message_id) if self.header.parent_message_id else None,
            "payload": self.payload.dict()
        }

class CommandMessage(Message):
    """Specialized message for commands between agents"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.COMMAND,
            priority=MessagePriority.NORMAL
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "command": "",
                "parameters": {},
                "expected_response_type": ""
            }
        )
    )

class ResponseMessage(Message):
    """Specialized message for responses to commands"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.RESPONSE,
            priority=MessagePriority.NORMAL
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "status": "",  # success, partial, error
                "data": {},
                "errors": [],
                "warnings": []
            }
        )
    )

class BroadcastMessage(Message):
    """Message broadcast to multiple agents"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.BROADCAST,
            is_broadcast=True,
            requires_ack=False
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "announcement": "",
                "context": {},
                "action_required": False
            }
        )
    )

class LogMessage(Message):
    """Structured log message"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.LOG,
            priority=MessagePriority.LOW,
            requires_ack=False
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "level": "info",  # debug, info, warning, error, critical
                "message": "",
                "source": "",
                "context": {}
            }
        )
    )

class AlertMessage(Message):
    """Alert message for important notifications"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.ALERT,
            priority=MessagePriority.HIGH
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "severity": "medium",  # low, medium, high, critical
                "title": "",
                "description": "",
                "recommended_actions": [],
                "related_resources": []
            }
        )
    )

class TaskUpdateMessage(Message):
    """Update on task progress"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.TASK_UPDATE,
            priority=MessagePriority.NORMAL
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "task_id": "",
                "status": "",  # started, in_progress, paused, completed, failed
                "progress": 0.0,  # 0-100
                "details": {}
            }
        )
    )

class ErrorMessage(Message):
    """Error message format"""
    header: MessageHeader = Field(
        default_factory=lambda: MessageHeader(
            message_type=MessageType.ERROR,
            priority=MessagePriority.HIGH
        )
    )
    payload: MessagePayload = Field(
        default_factory=lambda: MessagePayload(
            content={
                "error_type": "",
                "error_message": "",
                "stack_trace": "",
                "context": {}
            }
        )
    )
