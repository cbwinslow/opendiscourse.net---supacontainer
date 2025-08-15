import asyncio
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Union
from uuid import UUID, uuid4
import json

from ..schemas.agents import AgentDefinition, AgentStatus, AgentMetrics, AgentCapabilities, AgentState, AgentType
from ..schemas.messages import Message, MessageHeader, MessageType, MessagePriority, LogMessage, ErrorMessage, CommandMessage, ResponseMessage, BroadcastMessage
from ..schemas.crews import CrewDefinition, CrewMember, CrewRole
from ..base_agent import BaseAgent

class LoggerAgent(BaseAgent):
    """Specialized agent for logging and monitoring other agents"""
    
    def __init__(self, agent_definition: Optional[AgentDefinition] = None):
        """Initialize the logger agent"""
        if agent_definition is None:
            agent_definition = self._create_default_definition()
        
        super().__init__(agent_definition)
        self.log_buffer: List[Dict[str, Any]] = []
        self.max_buffer_size = 1000
        self.last_flush = datetime.utcnow()
        self.flush_interval = 60  # seconds
        self.log_storage: Dict[str, List[Dict[str, Any]]] = {
            'debug': [],
            'info': [],
            'warning': [],
            'error': [],
            'critical': []
        }
        self.metrics = {
            'logs_processed': 0,
            'log_ingest_errors': 0,
            'last_ingest_time': None,
            'ingest_rate': 0.0,
            'log_level_distribution': {level: 0 for level in self.log_storage.keys()}
        }
        self.retention_policies = {
            'debug': timedelta(days=7),
            'info': timedelta(days=30),
            'warning': timedelta(days=90),
            'error': timedelta(days=365),
            'critical': timedelta(days=365 * 2)
        }
    
    @classmethod
    def _create_default_definition(cls) -> AgentDefinition:
        """Create a default agent definition for the logger"""
        from ..schemas.agents import AgentIdentity, AgentCapabilities, AgentConfig, AgentDependencies, AgentState
        
        identity = AgentIdentity(
            name="SystemLogger",
            agent_type=AgentType.MONITORING,
            description="Central logging agent for the system",
            version="1.0.0"
        )
        
        capabilities = AgentCapabilities(
            read=True,
            write=True,
            monitor=True,
            alert=True,
            analyze=True
        )
        
        config = AgentConfig(
            log_level="DEBUG",
            max_retry_attempts=3,
            retry_delay_seconds=5,
            heartbeat_interval_seconds=30,
            log_retention_days=30,
            data_retention_days=90,
            backup_enabled=True,
            backup_interval_hours=24,
            alert_on_errors=True,
            alert_on_warnings=True
        )
        
        dependencies = AgentDependencies(
            required_services=["database", "message_broker"],
            required_apis=["logging_api"],
            required_libraries=["pydantic", "asyncio", "logging"],
            required_credentials=["database_credentials", "message_broker_credentials"]
        )
        
        state = AgentState(
            status=AgentStatus.STARTING,
            metrics=AgentMetrics()
        )
        
        return AgentDefinition(
            identity=identity,
            capabilities=capabilities,
            config=config,
            dependencies=dependencies,
            state=state
        )
    
    def _register_message_handlers(self) -> Dict[str, Any]:
        """Register message handlers specific to the logger agent"""
        return {
            MessageType.LOG: self._handle_log_message,
            MessageType.ERROR: self._handle_error_message,
            MessageType.COMMAND: self._handle_command,
            MessageType.STATUS_UPDATE: self._handle_status_update,
            MessageType.ALERT: self._handle_alert
        }
    
    async def _do_background_work(self):
        """Perform background work like flushing logs and cleaning up"""
        await self._flush_logs_if_needed()
        await self._cleanup_old_logs()
        await self._update_metrics()
    
    async def _flush_logs_if_needed(self):
        """Flush logs if buffer is full or enough time has passed"""
        now = datetime.utcnow()
        if (len(self.log_buffer) >= self.max_buffer_size or 
            (now - self.last_flush).total_seconds() >= self.flush_interval):
            await self._flush_logs()
    
    async def _flush_logs(self):
        """Flush buffered logs to storage"""
        if not self.log_buffer:
            return
        
        try:
            # In a real implementation, this would write to a database
            for log_entry in self.log_buffer:
                level = log_entry.get('level', 'info').lower()
                if level in self.log_storage:
                    self.log_storage[level].append(log_entry)
                    self.metrics['log_level_distribution'][level] += 1
            
            self.metrics['logs_processed'] += len(self.log_buffer)
            self.log_buffer.clear()
            self.last_flush = datetime.utcnow()
            
            self.logger.debug(f"Flushed {len(self.log_buffer)} logs to storage")
        except Exception as e:
            self.metrics['log_ingest_errors'] += 1
            self.logger.error(f"Error flushing logs: {str(e)}", exc_info=True)
    
    async def _cleanup_old_logs(self):
        """Remove logs older than retention period"""
        now = datetime.utcnow()
        for level, logs in self.log_storage.items():
            retention = self.retention_policies.get(level, timedelta(days=30))
            cutoff = now - retention
            
            # Filter out old logs
            original_count = len(logs)
            self.log_storage[level] = [
                log for log in logs 
                if datetime.fromisoformat(log['timestamp']) > cutoff
            ]
            
            removed = original_count - len(self.log_storage[level])
            if removed > 0:
                self.logger.debug(f"Removed {removed} old {level} logs (retention: {retention.days} days)")
    
    async def _update_metrics(self):
        """Update metrics about logging activity"""
        now = datetime.utcnow()
        
        # Calculate ingest rate (logs per second)
        if self.metrics['last_ingest_time']:
            time_diff = (now - self.metrics['last_ingest_time']).total_seconds()
            if time_diff > 0:
                self.metrics['ingest_rate'] = len(self.log_buffer) / time_diff
        
        self.metrics['last_ingest_time'] = now
        
        # Update agent metrics
        self.definition.state.metrics.active_tasks = len(self.active_tasks)
        self.definition.state.metrics.memory_usage_mb = len(str(self.log_storage)) / (1024 * 1024)  # Rough estimate
    
    # Message handlers
    async def _handle_log_message(self, message: Message):
        """Handle incoming log messages"""
        try:
            log_entry = {
                'timestamp': message.header.timestamp.isoformat(),
                'level': message.payload.get('level', 'info'),
                'message': message.payload.get('message', ''),
                'source': message.payload.get('source', 'unknown'),
                'agent_id': str(message.header.source_agent_id),
                'context': message.payload.get('context', {})
            }
            
            # Add to buffer
            self.log_buffer.append(log_entry)
            
            # Forward to appropriate log level handler
            level = log_entry['level'].lower()
            if level in ['debug', 'info', 'warning', 'error', 'critical']:
                getattr(self.logger, level)(
                    f"[{log_entry['source']}] {log_entry['message']}",
                    extra={"context": log_entry['context']}
                )
            
            # Acknowledge receipt if requested
            if message.header.requires_ack:
                await self._send_acknowledgment(message)
                
        except Exception as e:
            self.metrics['log_ingest_errors'] += 1
            self.logger.error(f"Error processing log message: {str(e)}", exc_info=True)
    
    async def _handle_error_message(self, message: Message):
        """Handle error messages"""
        try:
            log_entry = {
                'timestamp': message.header.timestamp.isoformat(),
                'level': 'error',
                'message': f"{message.payload.get('error_type', 'UnknownError')}: {message.payload.get('error_message', 'No message')}",
                'source': message.payload.get('source', 'unknown'),
                'agent_id': str(message.header.source_agent_id),
                'context': {
                    'error_type': message.payload.get('error_type'),
                    'stack_trace': message.payload.get('stack_trace'),
                    **message.payload.get('context', {})
                }
            }
            
            # Add to buffer
            self.log_buffer.append(log_entry)
            
            # Log the error
            self.logger.error(
                log_entry['message'],
                extra={"context": log_entry['context']}
            )
            
            # Acknowledge receipt if requested
            if message.header.requires_ack:
                await self._send_acknowledgment(message)
                
        except Exception as e:
            self.metrics['log_ingest_errors'] += 1
            self.logger.error(f"Error processing error message: {str(e)}", exc_info=True)
    
    async def _handle_command(self, message: Message):
        """Handle command messages"""
        command = message.payload.get('command', '').lower()
        params = message.payload.get('parameters', {})
        
        try:
            if command == 'get_logs':
                # Get logs with filters
                level = params.get('level')
                source = params.get('source')
                limit = min(int(params.get('limit', 100)), 1000)  # Max 1000 logs
                
                logs = []
                if level and level in self.log_storage:
                    logs = self.log_storage[level][-limit:]
                else:
                    # Get from all levels if no specific level provided
                    for level_logs in self.log_storage.values():
                        logs.extend(level_logs[-limit:])
                
                # Filter by source if specified
                if source:
                    logs = [log for log in logs if log.get('source') == source]
                
                # Sort by timestamp
                logs.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
                
                # Apply limit again after filtering
                logs = logs[:limit]
                
                # Send response
                response = ResponseMessage(
                    status="success",
                    data={"logs": logs, "count": len(logs)},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_metrics':
                # Get current metrics
                response = ResponseMessage(
                    status="success",
                    data={
                        "metrics": self.metrics,
                        "buffer_size": len(self.log_buffer),
                        "storage_counts": {level: len(logs) for level, logs in self.log_storage.items()},
                        "retention_policies": {k: str(v) for k, v in self.retention_policies.items()}
                    },
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'flush_logs':
                # Force flush logs
                await self._flush_logs()
                response = ResponseMessage(
                    status="success",
                    data={"message": f"Flushed {len(self.log_buffer)} logs"},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'set_log_level':
                # Change log level
                level = params.get('level', '').upper()
                if hasattr(logging, level):
                    self.definition.config.log_level = level
                    self.logger.setLevel(level)
                    response = ResponseMessage(
                        status="success",
                        data={"message": f"Log level set to {level}"},
                        context={"command": command}
                    )
                else:
                    response = ResponseMessage(
                        status="error",
                        errors=[f"Invalid log level: {level}"],
                        context={"command": command}
                    )
                await self.send_message(message.header.source_agent_id, response)
                
            else:
                # Unknown command
                response = ResponseMessage(
                    status="error",
                    errors=[f"Unknown command: {command}"],
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
        except Exception as e:
            error_msg = f"Error executing command '{command}': {str(e)}"
            self.logger.error(error_msg, exc_info=True)
            response = ResponseMessage(
                status="error",
                errors=[error_msg],
                context={"command": command}
            )
            await self.send_message(message.header.source_agent_id, response)
    
    async def _handle_status_update(self, message: Message):
        """Handle status update messages"""
        # Log status updates at info level
        self.logger.info(
            f"Status update from {message.header.source_agent_id}: {message.payload}",
            extra={"payload": message.payload}
        )
    
    async def _handle_alert(self, message: Message):
        """Handle alert messages"""
        # Log alerts at warning level or higher depending on severity
        severity = message.payload.get('severity', 'medium').lower()
        log_method = getattr(self.logger, severity if hasattr(self.logger, severity) else 'warning')
        
        log_method(
            f"ALERT [{severity.upper()}] {message.payload.get('title', 'No title')}",
            extra={
                "description": message.payload.get('description'),
                "recommended_actions": message.payload.get('recommended_actions', []),
                "source_agent_id": str(message.header.source_agent_id)
            }
        )
        
        # If critical, also log to error level
        if severity == 'critical':
            self.logger.error(
                f"CRITICAL ALERT: {message.payload.get('title')}",
                extra=message.payload
            )
    
    async def _send_acknowledgment(self, original_message: Message):
        """Send acknowledgment for a received message"""
        ack = ResponseMessage(
            status="acknowledged",
            data={
                "original_message_id": str(original_message.header.message_id),
                "received_at": datetime.utcnow().isoformat(),
                "status": "processed"
            },
            context={"component": "logger_agent"}
        )
        
        # Set correlation ID to match original message
        ack.header.correlation_id = original_message.header.message_id
        
        await self.send_message(original_message.header.source_agent_id, ack)
    
    # Public API methods
    async def get_logs(self, level: Optional[str] = None, source: Optional[str] = None, limit: int = 100) -> List[Dict[str, Any]]:
        """Get logs with optional filtering"""
        logs = []
        if level and level in self.log_storage:
            logs = self.log_storage[level][-limit:]
        else:
            for level_logs in self.log_storage.values():
                logs.extend(level_logs[-limit:])
        
        if source:
            logs = [log for log in logs if log.get('source') == source]
        
        logs.sort(key=lambda x: x.get('timestamp', ''), reverse=True)
        return logs[:limit]
    
    async def get_metrics(self) -> Dict[str, Any]:
        """Get current metrics"""
        return {
            "metrics": self.metrics,
            "buffer_size": len(self.log_buffer),
            "storage_counts": {level: len(logs) for level, logs in self.log_storage.items()},
            "retention_policies": {k: str(v) for k, v in self.retention_policies.items()}
        }
    
    async def flush_logs(self):
        """Force flush logs to storage"""
        await self._flush_logs()
        return {"status": "success", "message": f"Flushed {len(self.log_buffer)} logs"}
    
    def __str__(self):
        """String representation of the logger agent"""
        return f"LoggerAgent(id={self.id}, logs_processed={self.metrics['logs_processed']}, errors={self.metrics['log_ingest_errors']})"
