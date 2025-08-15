import asyncio
import logging
import time
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Callable, Coroutine, Type, TypeVar, Union
from uuid import UUID, uuid4
import json

from .schemas.agents import AgentDefinition, AgentStatus, AgentMetrics, AgentCapabilities, AgentState
from .schemas.messages import Message, MessageHeader, MessageType, MessagePriority, LogMessage, ErrorMessage, CommandMessage, ResponseMessage, BroadcastMessage
from .schemas.crews import CrewDefinition, CrewMember, CrewRole

T = TypeVar('T', bound='BaseAgent')

class BaseAgent:
    """Base class for all AI agents with core messaging and lifecycle management"""
    
    def __init__(self, agent_definition: AgentDefinition):
        """Initialize the agent with its definition"""
        self.definition = agent_definition
        self.id = agent_definition.identity.agent_id
        self.name = agent_definition.identity.name
        self.logger = self._setup_logger()
        self.message_handlers = self._register_message_handlers()
        self.running = False
        self.task_queue = asyncio.Queue()
        self.active_tasks: Dict[UUID, asyncio.Task] = {}
        self.message_history: List[Message] = []
        self.crew_memberships: Dict[UUID, CrewMember] = {}
        self.crew_roles: Dict[UUID, CrewRole] = {}
        self.last_heartbeat = datetime.utcnow()
        
        # Register default message handlers
        self._register_default_handlers()
    
    def _setup_logger(self) -> logging.Logger:
        """Set up the agent's logger"""
        logger = logging.getLogger(f"agent.{self.name.lower().replace(' ', '_')}")
        logger.setLevel(self.definition.config.log_level)
        
        # Create console handler
        ch = logging.StreamHandler()
        ch.setLevel(self.definition.config.log_level)
        
        # Create formatter and add it to the handlers
        formatter = logging.Formatter(
            f'%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        ch.setFormatter(formatter)
        
        # Add the handlers to the logger
        if not logger.handlers:
            logger.addHandler(ch)
        
        return logger
    
    def _register_default_handlers(self):
        """Register default message handlers"""
        self.message_handlers.update({
            MessageType.COMMAND: self._handle_command,
            MessageType.RESPONSE: self._handle_response,
            MessageType.BROADCAST: self._handle_broadcast,
            MessageType.LOG: self._handle_log,
            MessageType.ERROR: self._handle_error,
        })
    
    def _register_message_handlers(self) -> Dict[str, Callable[[Message], Coroutine[Any, Any, None]]]:
        """Register message handlers - to be overridden by subclasses"""
        return {}
    
    async def start(self):
        """Start the agent's main loop"""
        if self.running:
            self.logger.warning("Agent is already running")
            return
        
        self.running = True
        self.definition.state.status = AgentStatus.IDLE
        self.logger.info(f"Starting agent: {self.name} (ID: {self.id})")
        
        # Start the main task
        self.main_task = asyncio.create_task(self._run())
        
        # Start the heartbeat
        self.heartbeat_task = asyncio.create_task(self._heartbeat())
        
        # Announce startup
        await self.broadcast(
            f"Agent {self.name} has started",
            message_type=MessageType.STATUS_UPDATE,
            priority=MessagePriority.LOW
        )
    
    async def stop(self):
        """Gracefully stop the agent"""
        if not self.running:
            return
            
        self.logger.info("Stopping agent...")
        self.running = False
        
        # Cancel all tasks
        for task_id, task in list(self.active_tasks.items()):
            if not task.done():
                task.cancel()
        
        # Wait for tasks to complete
        if self.active_tasks:
            await asyncio.wait(list(self.active_tasks.values()))
        
        # Send shutdown notification
        await self.broadcast(
            f"Agent {self.name} is shutting down",
            message_type=MessageType.STATUS_UPDATE,
            priority=MessagePriority.NORMAL
        )
        
        # Update status
        self.definition.state.status = AgentStatus.TERMINATED
        self.logger.info("Agent stopped")
    
    async def _run(self):
        """Main agent loop"""
        try:
            while self.running:
                try:
                    # Process messages from the queue
                    message = await asyncio.wait_for(self.task_queue.get(), timeout=1.0)
                    await self._process_message(message)
                except asyncio.TimeoutError:
                    # No messages, do background work
                    await self._do_background_work()
                except Exception as e:
                    self.logger.error(f"Error in agent loop: {str(e)}", exc_info=True)
                    await self._handle_error(ErrorMessage(
                        error_type=type(e).__name__,
                        error_message=str(e),
                        context={"component": "agent_loop"}
                    ))
        except asyncio.CancelledError:
            self.logger.info("Agent loop cancelled")
        except Exception as e:
            self.logger.critical(f"Critical error in agent loop: {str(e)}", exc_info=True)
            await self.stop()
    
    async def _process_message(self, message: Message):
        """Process an incoming message"""
        try:
            # Log the message
            self.message_history.append(message)
            
            # Update metrics
            self.definition.state.metrics.total_tasks_processed += 1
            
            # Handle the message based on its type
            handler = self.message_handlers.get(message.header.message_type)
            if handler:
                # Create a task to handle the message
                task_id = uuid4()
                task = asyncio.create_task(self._execute_handler(handler, message, task_id))
                self.active_tasks[task_id] = task
                task.add_done_callback(lambda t, tid=task_id: self.active_tasks.pop(tid, None))
            else:
                self.logger.warning(f"No handler for message type: {message.header.message_type}")
        except Exception as e:
            self.logger.error(f"Error processing message: {str(e)}", exc_info=True)
            await self._handle_error(ErrorMessage(
                error_type=type(e).__name__,
                error_message=str(e),
                context={"component": "process_message", "message_id": str(message.header.message_id)}
            ))
    
    async def _execute_handler(self, handler: Callable[[Message], Coroutine[Any, Any, None]], 
                             message: Message, task_id: UUID):
        """Execute a message handler with error handling"""
        try:
            await handler(message)
        except Exception as e:
            self.logger.error(f"Error in message handler: {str(e)}", exc_info=True)
            await self._handle_error(ErrorMessage(
                error_type=type(e).__name__,
                error_message=str(e),
                context={
                    "component": "message_handler",
                    "message_type": message.header.message_type,
                    "task_id": str(task_id)
                }
            ))
    
    async def _heartbeat(self):
        """Send periodic heartbeats"""
        try:
            while self.running:
                self.last_heartbeat = datetime.utcnow()
                self.definition.state.metrics.last_heartbeat = self.last_heartbeat
                
                # Update uptime
                uptime = (datetime.utcnow() - self.definition.identity.created_at).total_seconds()
                self.definition.state.metrics.uptime_seconds = uptime
                
                # Log status
                self.logger.debug(f"Heartbeat - Status: {self.definition.state.status}")
                
                # Sleep until next heartbeat
                await asyncio.sleep(self.definition.config.heartbeat_interval_seconds)
        except asyncio.CancelledError:
            self.logger.info("Heartbeat task cancelled")
        except Exception as e:
            self.logger.error(f"Error in heartbeat: {str(e)}", exc_info=True)
    
    async def _do_background_work(self):
        """Perform background work - to be overridden by subclasses"""
        pass
    
    # Message sending methods
    async def send_message(self, target_agent_id: UUID, message: Message):
        """Send a message to a specific agent"""
        if not isinstance(target_agent_id, UUID):
            target_agent_id = UUID(target_agent_id)
            
        # Set message headers if not already set
        if not message.header.message_id:
            message.header.message_id = uuid4()
        if not message.header.timestamp:
            message.header.timestamp = datetime.utcnow()
        if not message.header.source_agent_id:
            message.header.source_agent_id = self.id
            
        # Add target agent
        message.header.target_agent_ids = [target_agent_id]
        
        # Log the message
        self.logger.debug(f"Sending message to agent {target_agent_id}: {message}")
        
        # In a real implementation, this would send the message to a message broker
        # For now, we'll just log it
        self.message_history.append(message)
        
        return message.header.message_id
    
    async def broadcast(self, content: Any, 
                       message_type: MessageType = MessageType.BROADCAST,
                       priority: MessagePriority = MessagePriority.NORMAL,
                       target_crews: Optional[List[UUID]] = None,
                       target_roles: Optional[List[UUID]] = None,
                       **kwargs) -> UUID:
        """Broadcast a message to multiple agents"""
        message_id = uuid4()
        
        # Create the message
        message = Message(
            header=MessageHeader(
                message_id=message_id,
                timestamp=datetime.utcnow(),
                message_type=message_type,
                priority=priority,
                source_agent_id=self.id,
                is_broadcast=True,
                requires_ack=False
            ),
            payload={
                "content": content,
                "target_crews": target_crews or [],
                "target_roles": target_roles or [],
                **kwargs
            }
        )
        
        # Log the broadcast
        self.logger.info(f"Broadcasting message: {message_id}")
        
        # In a real implementation, this would publish to a message broker
        # For now, we'll just log it
        self.message_history.append(message)
        
        return message_id
    
    # Message handler stubs - to be overridden by subclasses
    async def _handle_command(self, message: Message):
        """Handle command messages"""
        self.logger.warning(f"No command handler implemented for message: {message}")
    
    async def _handle_response(self, message: Message):
        """Handle response messages"""
        self.logger.debug(f"Received response: {message}")
    
    async def _handle_broadcast(self, message: Message):
        """Handle broadcast messages"""
        self.logger.debug(f"Received broadcast: {message}")
    
    async def _handle_log(self, message: Message):
        """Handle log messages"""
        log_level = message.payload.get("level", "info").upper()
        log_message = message.payload.get("message", "")
        source = message.payload.get("source", "unknown")
        
        log_method = getattr(self.logger, log_level.lower(), self.logger.info)
        log_method(f"[{source}] {log_message}")
    
    async def _handle_error(self, error: Union[ErrorMessage, Exception]):
        """Handle error messages and exceptions"""
        if isinstance(error, Exception):
            error = ErrorMessage(
                error_type=type(error).__name__,
                error_message=str(error),
                context={"component": "unknown"}
            )
        
        # Log the error
        self.logger.error(
            f"Error: {error.error_type} - {error.error_message}",
            extra={"context": error.context}
        )
        
        # Update error count
        self.definition.state.metrics.error_count += 1
        
        # Notify monitoring if configured
        if self.definition.config.alert_on_errors:
            await self.broadcast(
                f"Error in {self.name}: {error.error_type} - {error.error_message}",
                message_type=MessageType.ALERT,
                priority=MessagePriority.HIGH,
                error_type=error.error_type,
                error_message=error.error_message,
                context=error.context
            )
    
    # Crew management
    async def join_crew(self, crew: CrewDefinition, role: CrewRole):
        """Join a crew with a specific role"""
        if crew.crew_id in self.crew_memberships:
            self.logger.warning(f"Already a member of crew: {crew.crew_id}")
            return False
        
        # Create crew membership
        membership = CrewMember(
            agent_id=self.id,
            role_id=role.role_id,
            join_date=datetime.utcnow(),
            is_active=True
        )
        
        # Add to crew
        crew.members[uuid4()] = membership
        self.crew_memberships[crew.crew_id] = membership
        self.crew_roles[role.role_id] = role
        
        self.logger.info(f"Joined crew {crew.name} as {role.name}")
        return True
    
    async def leave_crew(self, crew_id: UUID):
        """Leave a crew"""
        if crew_id not in self.crew_memberships:
            self.logger.warning(f"Not a member of crew: {crew_id}")
            return False
        
        # Deactivate membership
        self.crew_memberships[crew_id].is_active = False
        self.crew_memberships[crew_id].leave_date = datetime.utcnow()
        
        # Remove role associations
        role_id = self.crew_memberships[crew_id].role_id
        if role_id in self.crew_roles:
            del self.crew_roles[role_id]
        
        self.logger.info(f"Left crew: {crew_id}")
        return True
    
    # Utility methods
    def get_status(self) -> Dict[str, Any]:
        """Get current agent status"""
        return {
            "agent_id": str(self.id),
            "name": self.name,
            "status": self.definition.state.status,
            "capabilities": self.definition.capabilities.dict(),
            "metrics": self.definition.state.metrics.dict(),
            "active_tasks": len(self.active_tasks),
            "message_queue_size": self.task_queue.qsize(),
            "last_heartbeat": self.last_heartbeat.isoformat() if self.last_heartbeat else None,
            "crew_memberships": [str(crew_id) for crew_id in self.crew_memberships],
            "crew_roles": [str(role_id) for role_id in self.crew_roles]
        }
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert agent to dictionary"""
        return {
            "id": str(self.id),
            "name": self.name,
            "type": self.definition.identity.agent_type,
            "status": self.definition.state.status,
            "capabilities": self.definition.capabilities.dict(),
            "config": self.definition.config.dict(),
            "state": self.definition.state.dict(),
            "crew_memberships": [
                {"crew_id": str(crew_id), "role_id": str(member.role_id), "is_active": member.is_active}
                for crew_id, member in self.crew_memberships.items()
            ]
        }
    
    def __str__(self) -> str:
        """String representation of the agent"""
        return f"{self.__class__.__name__}(id={self.id}, name='{self.name}', status={self.definition.state.status})"
    
    def __repr__(self) -> str:
        """Official string representation"""
        return f"<{self.__class__.__name__} id={self.id} name='{self.name}'>"
