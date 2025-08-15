import asyncio
import logging
import re
import socket
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set, Tuple
from uuid import UUID, uuid4

from ..schemas.agents import AgentDefinition, AgentStatus, AgentCapabilities, AgentType, AgentState, AgentMetrics, AgentIdentity, AgentConfig, AgentDependencies
from ..schemas.messages import Message, MessageHeader, MessageType, MessagePriority, AlertMessage, CommandMessage, ResponseMessage, BroadcastMessage
from ..schemas.crews import CrewDefinition, CrewMember, CrewRole
from ..base_agent import BaseAgent

class SecurityAgent(BaseAgent):
    """Specialized agent for security monitoring and response"""
    
    def __init__(self, agent_definition: Optional[AgentDefinition] = None):
        """Initialize the security agent"""
        if agent_definition is None:
            agent_definition = self._create_default_definition()
        
        super().__init__(agent_definition)
        
        # Security monitoring state
        self.suspicious_ips: Dict[str, Dict] = {}
        self.failed_login_attempts: Dict[str, List[datetime]] = {}
        self.known_threats: Set[str] = set()
        self.security_events: List[Dict] = []
        self.whitelist: Set[str] = set()
        self.blacklist: Set[str] = set()
        
        # Rate limiting
        self.login_attempt_window = timedelta(minutes=5)
        self.max_login_attempts = 5
        
        # Threat intelligence
        self.threat_intel_sources = [
            "https://www.blocklist.de/en/export.html",
            "https://check.torproject.org/exit-addresses",
            "https://www.binarydefense.com/banlist.txt"
        ]
        
        # Update threat intelligence on startup
        self.update_task = asyncio.create_task(self._update_threat_intelligence())
    
    @classmethod
    def _create_default_definition(cls) -> AgentDefinition:
        """Create a default agent definition for the security agent"""
        identity = AgentIdentity(
            name="SecurityMonitor",
            agent_type=AgentType.SECURITY,
            description="Monitors and responds to security events across the system",
            version="1.0.0"
        )
        
        capabilities = AgentCapabilities(
            read=True,
            monitor=True,
            alert=True,
            secure=True,
            audit=True
        )
        
        config = AgentConfig(
            log_level="INFO",
            max_retry_attempts=3,
            retry_delay_seconds=5,
            heartbeat_interval_seconds=30,
            log_retention_days=90,
            data_retention_days=180,
            backup_enabled=True,
            backup_interval_hours=24,
            alert_on_errors=True,
            alert_on_warnings=True
        )
        
        dependencies = AgentDependencies(
            required_services=["firewall", "ids", "log_aggregator"],
            required_apis=["threat_intel"],
            required_libraries=["pydantic", "asyncio", "aiohttp"],
            required_credentials=["threat_intel_api_key"]
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
        """Register message handlers specific to the security agent"""
        return {
            MessageType.LOG: self._handle_log_message,
            MessageType.ALERT: self._handle_alert_message,
            MessageType.COMMAND: self._handle_command,
            MessageType.STATUS_UPDATE: self._handle_status_update
        }
    
    async def _do_background_work(self):
        """Perform background security tasks"""
        # Rotate logs if needed
        if len(self.security_events) > 10000:  # Keep last 10k events in memory
            self.security_events = self.security_events[-10000:]
        
        # Clean up old failed login attempts
        self._cleanup_failed_logins()
        
        # Update threat intelligence periodically
        if self.update_task.done():
            self.update_task = asyncio.create_task(self._update_threat_intelligence())
    
    async def _update_threat_intelligence(self):
        """Update threat intelligence from external sources"""
        try:
            self.logger.info("Updating threat intelligence...")
            
            # In a real implementation, this would fetch from external sources
            # For now, we'll just simulate it with some known bad IPs
            new_threats = {
                "1.2.3.4", "5.6.7.8", "9.10.11.12",
                "185.220.101.4",  # Known Tor exit node
                "45.155.205.233",  # Known malicious IP
                "91.219.236.197"   # Known scanner
            }
            
            added = new_threats - self.known_threats
            if added:
                self.known_threats.update(added)
                self.logger.info(f"Added {len(added)} new threats to intelligence")
                
                # Notify about new threats
                await self.broadcast(
                    f"Added {len(added)} new threats to intelligence database",
                    message_type=MessageType.STATUS_UPDATE,
                    priority=MessagePriority.NORMAL
                )
            
            # Update metrics
            self.definition.state.metrics.metadata["threat_intel_count"] = len(self.known_threats)
            
        except Exception as e:
            self.logger.error(f"Error updating threat intelligence: {str(e)}", exc_info=True)
            
        # Schedule next update in 1 hour
        await asyncio.sleep(3600)
    
    def _cleanup_failed_logins(self):
        """Remove old failed login attempts"""
        cutoff = datetime.utcnow() - self.login_attempt_window
        for ip, attempts in list(self.failed_login_attempts.items()):
            # Remove old attempts
            recent_attempts = [t for t in attempts if t > cutoff]
            
            if recent_attempts:
                self.failed_login_attempts[ip] = recent_attempts
            else:
                del self.failed_login_attempts[ip]
    
    def _is_suspicious_ip(self, ip: str) -> bool:
        """Check if an IP is suspicious"""
        # Check blacklist
        if ip in self.blacklist:
            return True
            
        # Check whitelist
        if ip in self.whitelist:
            return False
            
        # Check known threats
        if ip in self.known_threats:
            return True
            
        # Check for too many failed login attempts
        if ip in self.failed_login_attempts:
            recent_attempts = [
                t for t in self.failed_login_attempts[ip]
                if t > datetime.utcnow() - self.login_attempt_window
            ]
            if len(recent_attempts) >= self.max_login_attempts:
                return True
                
        return False
    
    def _record_security_event(self, event_type: str, severity: str, details: Dict, source: str = "security_agent") -> Dict:
        """Record a security event"""
        event = {
            "event_id": str(uuid4()),
            "timestamp": datetime.utcnow().isoformat(),
            "type": event_type,
            "severity": severity,
            "source": source,
            "details": details
        }
        
        self.security_events.append(event)
        self.logger.info(f"Security event: {event_type} - {severity}", extra={"event": event})
        
        return event
    
    async def _handle_log_message(self, message: Message):
        """Handle log messages for security analysis"""
        try:
            log_level = message.payload.get('level', '').lower()
            log_message = message.payload.get('message', '')
            source = message.payload.get('source', 'unknown')
            context = message.payload.get('context', {})
            
            # Skip if not a security-relevant log level
            if log_level not in ['warning', 'error', 'critical']:
                return
            
            # Extract IPs from log message
            ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}\b|\b(?:[A-Fa-f0-9]{1,4}::?){1,7}[A-Fa-f0-9]{1,4}\b'
            ips = re.findall(ip_pattern, log_message)
            
            # Check each IP
            for ip in ips:
                if self._is_suspicious_ip(ip):
                    # Record security event
                    event = self._record_security_event(
                        event_type="suspicious_ip_detected",
                        severity="high",
                        details={
                            "ip": ip,
                            "source_log": log_message,
                            "context": context
                        },
                        source=source
                    )
                    
                    # Take action based on severity
                    await self._respond_to_threat(ip, event)
            
            # Check for security-related patterns
            security_patterns = {
                'brute force': 'brute_force_attempt',
                'password fail': 'failed_login',
                'unauthorized': 'unauthorized_access',
                'sql injection': 'sql_injection_attempt',
                'xss': 'xss_attempt',
                'exploit': 'exploit_attempt',
                'malware': 'malware_detected',
                'virus': 'virus_detected',
                'backdoor': 'backdoor_detected',
                'rootkit': 'rootkit_detected'
            }
            
            for pattern, event_type in security_patterns.items():
                if pattern in log_message.lower():
                    event = self._record_security_event(
                        event_type=event_type,
                        severity="high" if 'attempt' in event_type else "critical",
                        details={
                            "message": log_message,
                            "context": context,
                            "source": source
                        },
                        source=source
                    )
                    
                    # Take action
                    await self._respond_to_threat("", event)
        
        except Exception as e:
            self.logger.error(f"Error processing log message: {str(e)}", exc_info=True)
    
    async def _respond_to_threat(self, ip: str, event: Dict):
        """Take appropriate action in response to a detected threat"""
        try:
            event_type = event.get('type', '')
            severity = event.get('severity', 'medium')
            
            # Default actions based on event type and severity
            actions = []
            
            if 'brute_force' in event_type or 'failed_login' in event_type:
                # Add IP to blacklist temporarily
                self.blacklist.add(ip)
                actions.append(f"Temporarily blacklisted IP: {ip}")
                
                # Notify administrators
                await self.broadcast(
                    f"Potential brute force attempt from {ip}",
                    message_type=MessageType.ALERT,
                    severity=severity,
                    details=event.get('details', {})
                )
            
            elif 'malware' in event_type or 'virus' in event_type:
                # Trigger system scan
                actions.append("Initiating full system scan")
                
                # Isolate affected system if possible
                await self.broadcast(
                    "Malware detected. Isolating affected systems.",
                    message_type=MessageType.ALERT,
                    severity="critical",
                    details=event.get('details', {})
                )
            
            # Log the actions taken
            event['actions_taken'] = actions
            self.logger.warning(
                f"Responded to {event_type} threat",
                extra={"event": event, "actions": actions}
            )
            
        except Exception as e:
            self.logger.error(f"Error responding to threat: {str(e)}", exc_info=True)
    
    async def _handle_alert_message(self, message: Message):
        """Handle alert messages from other agents"""
        try:
            alert = message.payload
            severity = alert.get('severity', 'medium')
            title = alert.get('title', 'Untitled Alert')
            description = alert.get('description', '')
            
            # Log the alert
            self.logger.warning(
                f"SECURITY ALERT: {title}",
                extra={
                    "severity": severity,
                    "description": description,
                    "source_agent": str(message.header.source_agent_id),
                    "recommended_actions": alert.get('recommended_actions', [])
                }
            )
            
            # Record as security event
            self._record_security_event(
                event_type="security_alert",
                severity=severity,
                details={
                    "title": title,
                    "description": description,
                    "source_agent": str(message.header.source_agent_id),
                    "recommended_actions": alert.get('recommended_actions', [])
                },
                source=str(message.header.source_agent_id)
            )
            
        except Exception as e:
            self.logger.error(f"Error processing alert message: {str(e)}", exc_info=True)
    
    async def _handle_command(self, message: Message):
        """Handle command messages"""
        try:
            command = message.payload.get('command', '').lower()
            params = message.payload.get('parameters', {})
            
            if command == 'get_security_events':
                # Get security events with filters
                event_type = params.get('type')
                severity = params.get('severity')
                limit = min(int(params.get('limit', 100)), 1000)
                
                events = self.security_events
                
                if event_type:
                    events = [e for e in events if e.get('type') == event_type]
                if severity:
                    events = [e for e in events if e.get('severity') == severity]
                
                # Apply limit
                events = events[-limit:]
                
                # Send response
                response = ResponseMessage(
                    status="success",
                    data={"events": events, "count": len(events)},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'add_to_blacklist':
                # Add IP to blacklist
                ip = params.get('ip')
                if not ip:
                    raise ValueError("IP address is required")
                
                self.blacklist.add(ip)
                
                response = ResponseMessage(
                    status="success",
                    data={"message": f"Added {ip} to blacklist"},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'remove_from_blacklist':
                # Remove IP from blacklist
                ip = params.get('ip')
                if not ip:
                    raise ValueError("IP address is required")
                
                if ip in self.blacklist:
                    self.blacklist.remove(ip)
                    
                response = ResponseMessage(
                    status="success",
                    data={"message": f"Removed {ip} from blacklist"},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_blacklist':
                # Get current blacklist
                response = ResponseMessage(
                    status="success",
                    data={"blacklist": list(self.blacklist)},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_whitelist':
                # Get current whitelist
                response = ResponseMessage(
                    status="success",
                    data={"whitelist": list(self.whitelist)},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'add_to_whitelist':
                # Add IP to whitelist
                ip = params.get('ip')
                if not ip:
                    raise ValueError("IP address is required")
                
                self.whitelist.add(ip)
                
                response = ResponseMessage(
                    status="success",
                    data={"message": f"Added {ip} to whitelist"},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'remove_from_whitelist':
                # Remove IP from whitelist
                ip = params.get('ip')
                if not ip:
                    raise ValueError("IP address is required")
                
                if ip in self.whitelist:
                    self.whitelist.remove(ip)
                    
                response = ResponseMessage(
                    status="success",
                    data={"message": f"Removed {ip} from whitelist"},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_threat_intel':
                # Get current threat intelligence
                response = ResponseMessage(
                    status="success",
                    data={
                        "known_threats": list(self.known_threats),
                        "threat_count": len(self.known_threats),
                        "last_updated": self.update_task.done() and self.update_task.result() or None
                    },
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'update_threat_intel':
                # Force update of threat intelligence
                if not self.update_task.done():
                    self.update_task.cancel()
                self.update_task = asyncio.create_task(self._update_threat_intelligence())
                
                response = ResponseMessage(
                    status="success",
                    data={"message": "Updating threat intelligence..."},
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
    
    async def get_status(self) -> Dict[str, Any]:
        """Get current security status"""
        return {
            "agent_id": str(self.id),
            "name": self.name,
            "status": self.definition.state.status,
            "security_events": len(self.security_events),
            "known_threats": len(self.known_threats),
            "blacklist_size": len(self.blacklist),
            "whitelist_size": len(self.whitelist),
            "failed_login_attempts": len(self.failed_login_attempts),
            "last_heartbeat": self.last_heartbeat.isoformat() if hasattr(self, 'last_heartbeat') else None,
            "threat_intel_last_updated": self.update_task.done() and self.update_task.result() or None
        }
    
    def __str__(self):
        """String representation of the security agent"""
        return (f"SecurityAgent(id={self.id}, events={len(self.security_events)}, "
                f"threats={len(self.known_threats)}, blacklist={len(self.blacklist)})")
