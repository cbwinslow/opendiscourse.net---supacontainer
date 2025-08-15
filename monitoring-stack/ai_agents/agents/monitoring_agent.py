import asyncio
import logging
import psutil
import platform
import socket
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Any, Set, Tuple
from uuid import UUID, uuid4

from ..schemas.agents import AgentDefinition, AgentStatus, AgentCapabilities, AgentType, AgentState, AgentMetrics, AgentIdentity, AgentConfig, AgentDependencies
from ..schemas.messages import Message, MessageHeader, MessageType, MessagePriority, AlertMessage, CommandMessage, ResponseMessage, BroadcastMessage, MetricMessage
from ..schemas.crews import CrewDefinition, CrewMember, CrewRole
from ..base_agent import BaseAgent

class MonitoringAgent(BaseAgent):
    """Specialized agent for system and application monitoring"""
    
    def __init__(self, agent_definition: Optional[AgentDefinition] = None):
        """Initialize the monitoring agent"""
        if agent_definition is None:
            agent_definition = self._create_default_definition()
        
        super().__init__(agent_definition)
        
        # Monitoring state
        self.metrics_history: Dict[str, List[Dict]] = {
            'cpu': [],
            'memory': [],
            'disk': [],
            'network': []
        }
        self.max_metrics_history = 1000
        self.last_metrics_update = datetime.utcnow()
        self.metrics_interval = 60  # seconds
        
        # Thresholds for alerts
        self.thresholds = {
            'cpu_percent': 90.0,
            'memory_percent': 85.0,
            'disk_percent': 90.0,
            'network_errors': 10  # per minute
        }
        
        # Track network errors
        self.network_error_counts: Dict[str, int] = {}
        self.last_network_check = datetime.utcnow()
        
        # Start metrics collection
        self.metrics_task = asyncio.create_task(self._collect_metrics_loop())
    
    @classmethod
    def _create_default_definition(cls) -> AgentDefinition:
        """Create a default agent definition for the monitoring agent"""
        identity = AgentIdentity(
            name="SystemMonitor",
            agent_type=AgentType.MONITORING,
            description="Monitors system and application metrics",
            version="1.0.0"
        )
        
        capabilities = AgentCapabilities(
            read=True,
            monitor=True,
            alert=True,
            analyze=True
        )
        
        config = AgentConfig(
            log_level="INFO",
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
            required_services=[],
            required_apis=[],
            required_libraries=["psutil", "platform"],
            required_credentials=[]
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
        """Register message handlers specific to the monitoring agent"""
        return {
            MessageType.COMMAND: self._handle_command,
            MessageType.STATUS_UPDATE: self._handle_status_update,
            MessageType.METRIC: self._handle_metric_message
        }
    
    async def _collect_metrics_loop(self):
        """Main loop for collecting system metrics"""
        while self.running:
            try:
                await self._collect_system_metrics()
                await asyncio.sleep(self.metrics_interval)
            except asyncio.CancelledError:
                break
            except Exception as e:
                self.logger.error(f"Error in metrics collection loop: {str(e)}", exc_info=True)
                await asyncio.sleep(5)  # Prevent tight loop on errors
    
    async def _collect_system_metrics(self):
        """Collect system metrics"""
        try:
            timestamp = datetime.utcnow()
            
            # CPU metrics
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_times = psutil.cpu_times_percent(interval=1)
            
            cpu_metrics = {
                'timestamp': timestamp.isoformat(),
                'cpu_percent': cpu_percent,
                'user': cpu_times.user,
                'system': cpu_times.system,
                'idle': cpu_times.idle,
                'iowait': getattr(cpu_times, 'iowait', 0),
                'irq': getattr(cpu_times, 'irq', 0),
                'softirq': getattr(cpu_times, 'softirq', 0),
                'steal': getattr(cpu_times, 'steal', 0),
                'guest': getattr(cpu_times, 'guest', 0),
                'guest_nice': getattr(cpu_times, 'guest_nice', 0)
            }
            
            # Memory metrics
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            
            memory_metrics = {
                'timestamp': timestamp.isoformat(),
                'total': memory.total,
                'available': memory.available,
                'percent': memory.percent,
                'used': memory.used,
                'free': memory.free,
                'active': getattr(memory, 'active', 0),
                'inactive': getattr(memory, 'inactive', 0),
                'buffers': getattr(memory, 'buffers', 0),
                'cached': getattr(memory, 'cached', 0),
                'shared': getattr(memory, 'shared', 0),
                'swap_total': swap.total,
                'swap_used': swap.used,
                'swap_free': swap.free,
                'swap_percent': swap.percent
            }
            
            # Disk metrics
            disk_metrics = []
            for partition in psutil.disk_partitions(all=False):
                try:
                    usage = psutil.disk_usage(partition.mountpoint)
                    disk_metrics.append({
                        'device': partition.device,
                        'mountpoint': partition.mountpoint,
                        'fstype': partition.fstype,
                        'opts': partition.opts,
                        'total': usage.total,
                        'used': usage.used,
                        'free': usage.free,
                        'percent': usage.percent
                    })
                except Exception as e:
                    self.logger.error(f"Error getting disk usage for {partition.mountpoint}: {str(e)}")
            
            # Network metrics
            net_io = psutil.net_io_counters()
            net_metrics = {
                'timestamp': timestamp.isoformat(),
                'bytes_sent': net_io.bytes_sent,
                'bytes_recv': net_io.bytes_recv,
                'packets_sent': net_io.packets_sent,
                'packets_recv': net_io.packets_recv,
                'errin': net_io.errin,
                'errout': net_io.errout,
                'dropin': net_io.dropin,
                'dropout': net_io.dropout
            }
            
            # Check for network errors
            if hasattr(self, 'last_net_io'):
                time_diff = (timestamp - self.last_net_io['timestamp']).total_seconds()
                if time_diff > 0:
                    err_rate = (net_io.errin + net_io.errout - 
                              (self.last_net_io['errin'] + self.last_net_io['errout'])) / time_diff * 60
                    
                    if err_rate > self.thresholds['network_errors']:
                        await self._trigger_alert(
                            "high_network_errors",
                            f"High network error rate detected: {err_rate:.2f} errors/minute",
                            {
                                'error_rate': err_rate,
                                'threshold': self.thresholds['network_errors'],
                                'errors_in': net_io.errin - self.last_net_io['errin'],
                                'errors_out': net_io.errout - self.last_net_io['errout']
                            }
                        )
            
            # Save current values for next comparison
            self.last_net_io = {
                'timestamp': timestamp,
                'errin': net_io.errin,
                'errout': net_io.errout
            }
            
            # Check thresholds and trigger alerts
            await self._check_thresholds({
                'cpu': cpu_metrics,
                'memory': memory_metrics,
                'network': net_metrics
            })
            
            # Store metrics
            self._store_metrics('cpu', cpu_metrics)
            self._store_metrics('memory', memory_metrics)
            self._store_metrics('network', net_metrics)
            
            # Store disk metrics for each partition
            for disk in disk_metrics:
                self._store_metrics('disk', disk)
            
            # Update last metrics time
            self.last_metrics_update = timestamp
            
            # Update agent metrics
            self.definition.state.metrics.memory_usage_mb = memory.used / (1024 * 1024)
            self.definition.state.metrics.cpu_usage = cpu_percent
            
        except Exception as e:
            self.logger.error(f"Error collecting system metrics: {str(e)}", exc_info=True)
    
    def _store_metrics(self, metric_type: str, metrics: Dict):
        """Store metrics in history"""
        if metric_type not in self.metrics_history:
            self.metrics_history[metric_type] = []
        
        self.metrics_history[metric_type].append(metrics)
        
        # Trim history
        if len(self.metrics_history[metric_type]) > self.max_metrics_history:
            self.metrics_history[metric_type] = self.metrics_history[metric_type][-self.max_metrics_history:]
    
    async def _check_thresholds(self, metrics: Dict[str, Dict]):
        """Check metrics against thresholds and trigger alerts"""
        # CPU check
        if 'cpu' in metrics and 'cpu_percent' in metrics['cpu']:
            cpu_percent = metrics['cpu']['cpu_percent']
            if cpu_percent > self.thresholds['cpu_percent']:
                await self._trigger_alert(
                    "high_cpu_usage",
                    f"High CPU usage detected: {cpu_percent:.1f}%",
                    {
                        'value': cpu_percent,
                        'threshold': self.thresholds['cpu_percent'],
                        'details': metrics['cpu']
                    }
                )
        
        # Memory check
        if 'memory' in metrics and 'percent' in metrics['memory']:
            mem_percent = metrics['memory']['percent']
            if mem_percent > self.thresholds['memory_percent']:
                await self._trigger_alert(
                    "high_memory_usage",
                    f"High memory usage detected: {mem_percent:.1f}%",
                    {
                        'value': mem_percent,
                        'threshold': self.thresholds['memory_percent'],
                        'details': metrics['memory']
                    }
                )
        
        # Disk check (for each partition)
        if 'disk' in metrics and isinstance(metrics['disk'], dict) and 'percent' in metrics['disk']:
            disk_percent = metrics['disk']['percent']
            if disk_percent > self.thresholds['disk_percent']:
                await self._trigger_alert(
                    "high_disk_usage",
                    f"High disk usage detected on {metrics['disk'].get('mountpoint', 'unknown')}: {disk_percent:.1f}%",
                    {
                        'value': disk_percent,
                        'threshold': self.thresholds['disk_percent'],
                        'details': metrics['disk']
                    }
                )
    
    async def _trigger_alert(self, alert_type: str, message: str, details: Dict):
        """Trigger an alert"""
        alert = AlertMessage(
            title=f"{alert_type.replace('_', ' ').title()}",
            description=message,
            severity="high",
            source_agent_id=self.id,
            details=details
        )
        
        # Broadcast the alert
        await self.broadcast(
            message,
            message_type=MessageType.ALERT,
            severity="high",
            alert_type=alert_type,
            details=details
        )
        
        self.logger.warning(f"Alert triggered: {message}", extra=details)
    
    async def _handle_metric_message(self, message: Message):
        """Handle incoming metric messages from other agents"""
        try:
            metric_type = message.payload.get('metric_type')
            metric_data = message.payload.get('data', {})
            
            if not metric_type or not metric_data:
                self.logger.warning("Invalid metric message: missing type or data")
                return
            
            # Add timestamp if not provided
            if 'timestamp' not in metric_data:
                metric_data['timestamp'] = datetime.utcnow().isoformat()
            
            # Store the metric
            self._store_metrics(metric_type, metric_data)
            
            # Check thresholds if applicable
            if 'value' in metric_data and 'threshold' in message.payload:
                threshold = message.payload['threshold']
                if metric_data['value'] > threshold:
                    await self._trigger_alert(
                        f"high_{metric_type}",
                        f"{metric_type} threshold exceeded: {metric_data['value']} > {threshold}",
                        {
                            'value': metric_data['value'],
                            'threshold': threshold,
                            'details': metric_data
                        }
                    )
            
        except Exception as e:
            self.logger.error(f"Error processing metric message: {str(e)}", exc_info=True)
    
    async def _handle_command(self, message: Message):
        """Handle command messages"""
        try:
            command = message.payload.get('command', '').lower()
            params = message.payload.get('parameters', {})
            
            if command == 'get_metrics':
                # Get metrics with filters
                metric_type = params.get('type')
                limit = min(int(params.get('limit', 100)), 1000)
                
                if metric_type and metric_type in self.metrics_history:
                    metrics = self.metrics_history[metric_type][-limit:]
                else:
                    metrics = {}
                    for mtype, values in self.metrics_history.items():
                        metrics[mtype] = values[-limit:]
                
                # Send response
                response = ResponseMessage(
                    status="success",
                    data={"metrics": metrics},
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_system_info':
                # Get system information
                system_info = {
                    'hostname': socket.gethostname(),
                    'os': f"{platform.system()} {platform.release()}",
                    'platform': platform.platform(),
                    'processor': platform.processor() or 'unknown',
                    'cpu_count': psutil.cpu_count(),
                    'boot_time': datetime.fromtimestamp(psutil.boot_time()).isoformat(),
                    'python_version': platform.python_version()
                }
                
                response = ResponseMessage(
                    status="success",
                    data=system_info,
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'get_processes':
                # Get running processes
                processes = []
                for proc in psutil.process_iter(['pid', 'name', 'username', 'cpu_percent', 'memory_percent']):
                    try:
                        processes.append(proc.info)
                    except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                        pass
                
                # Sort by CPU usage
                processes = sorted(processes, key=lambda p: p.get('cpu_percent', 0), reverse=True)
                
                response = ResponseMessage(
                    status="success",
                    data={"processes": processes[:100]},  # Limit to top 100
                    context={"command": command}
                )
                await self.send_message(message.header.source_agent_id, response)
                
            elif command == 'set_threshold':
                # Update a threshold
                threshold_name = params.get('name')
                threshold_value = params.get('value')
                
                if not threshold_name or threshold_value is None:
                    raise ValueError("Both 'name' and 'value' parameters are required")
                
                if threshold_name in self.thresholds:
                    old_value = self.thresholds[threshold_name]
                    self.thresholds[threshold_name] = float(threshold_value)
                    
                    response = ResponseMessage(
                        status="success",
                        data={
                            "message": f"Threshold '{threshold_name}' updated from {old_value} to {threshold_value}",
                            "thresholds": self.thresholds
                        },
                        context={"command": command}
                    )
                else:
                    response = ResponseMessage(
                        status="error",
                        errors=[f"Unknown threshold: {threshold_name}"],
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
        # Log status updates at debug level
        self.logger.debug(
            f"Status update from {message.header.source_agent_id}: {message.payload}",
            extra={"payload": message.payload}
        )
    
    async def get_status(self) -> Dict[str, Any]:
        """Get current monitoring status"""
        return {
            "agent_id": str(self.id),
            "name": self.name,
            "status": self.definition.state.status,
            "metrics_collected": {k: len(v) for k, v in self.metrics_history.items()},
            "last_metrics_update": self.last_metrics_update.isoformat() if self.last_metrics_update else None,
            "thresholds": self.thresholds,
            "cpu_usage": self.definition.state.metrics.cpu_usage,
            "memory_usage_mb": self.definition.state.metrics.memory_usage_mb
        }
    
    async def stop(self):
        """Clean up before stopping"""
        await super().stop()
        if hasattr(self, 'metrics_task') and not self.metrics_task.done():
            self.metrics_task.cancel()
    
    def __str__(self):
        """String representation of the monitoring agent"""
        return (f"MonitoringAgent(id={self.id}, metrics={sum(len(v) for v in self.metrics_history.values())}, "
                f"cpu={self.definition.state.metrics.cpu_usage}%)")
