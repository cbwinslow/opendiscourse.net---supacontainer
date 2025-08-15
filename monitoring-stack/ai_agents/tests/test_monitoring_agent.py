import asyncio
import pytest
import psutil
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, MagicMock, patch

from ..agents.monitoring_agent import MonitoringAgent
from ..schemas.agents import AgentDefinition, AgentStatus, AgentCapabilities, AgentType, AgentState, AgentMetrics, AgentIdentity, AgentConfig, AgentDependencies
from ..schemas.messages import Message, MessageHeader, MessageType, MessagePriority, AlertMessage, CommandMessage, ResponseMessage, BroadcastMessage, MetricMessage

@pytest.fixture
def mock_agent_definition():
    """Create a mock agent definition for testing"""
    identity = AgentIdentity(
        name="TestMonitor",
        agent_type=AgentType.MONITORING,
        description="Test monitoring agent",
        version="1.0.0"
    )
    
    capabilities = AgentCapabilities(
        read=True,
        monitor=True,
        alert=True,
        analyze=True
    )
    
    config = AgentConfig(
        log_level="DEBUG",
        max_retry_attempts=3,
        retry_delay_seconds=1,
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
        required_libraries=[],
        required_credentials=[]
    )
    
    state = AgentState(
        status=AgentStatus.RUNNING,
        metrics=AgentMetrics()
    )
    
    return AgentDefinition(
        identity=identity,
        capabilities=capabilities,
        config=config,
        dependencies=dependencies,
        state=state
    )

@pytest.fixture
def monitoring_agent(mock_agent_definition):
    """Create a monitoring agent instance for testing"""
    agent = MonitoringAgent(agent_definition=mock_agent_definition)
    agent.send_message = AsyncMock()
    agent.broadcast = AsyncMock()
    return agent

@pytest.mark.asyncio
async def test_monitoring_agent_initialization(monitoring_agent):
    """Test monitoring agent initialization"""
    assert monitoring_agent is not None
    assert monitoring_agent.definition.identity.name == "TestMonitor"
    assert monitoring_agent.definition.identity.agent_type == AgentType.MONITORING
    assert monitoring_agent.definition.state.status == AgentStatus.RUNNING

@pytest.mark.asyncio
async def test_collect_system_metrics(monitoring_agent):
    """Test collection of system metrics"""
    # Mock psutil functions
    with patch('psutil.cpu_percent', return_value=25.5), \
         patch('psutil.cpu_times_percent', return_value=type('obj', (object,), {
             'user': 10.1, 'system': 5.2, 'idle': 84.7,
             'iowait': 0.0, 'irq': 0.0, 'softirq': 0.0,
             'steal': 0.0, 'guest': 0.0, 'guest_nice': 0.0
         })), \
         patch('psutil.virtual_memory', return_value=type('obj', (object,), {
             'total': 8589934592, 'available': 5153960755, 'percent': 40.0,
             'used': 3435973837, 'free': 5153960755, 'active': 4294967296,
             'inactive': 2576980377, 'buffers': 107374182, 'cached': 2147483648,
             'shared': 107374182
         })), \
         patch('psutil.swap_memory', return_value=type('obj', (object,), {
             'total': 2147483648, 'used': 1073741824, 'free': 1073741824,
             'percent': 50.0
         })), \
         patch('psutil.disk_partitions', return_value=[
             type('obj', (object,), {
                 'device': '/dev/sda1',
                 'mountpoint': '/',
                 'fstype': 'ext4',
                 'opts': 'rw,relatime',
                 'maxfile': 255,
                 'maxpath': 4096
             })
         ]), \
         patch('psutil.disk_usage', return_value=type('obj', (object,), {
             'total': 107374182400, 'used': 53687091200, 'free': 53687091200,
             'percent': 50.0
         })), \
         patch('psutil.net_io_counters', return_value=type('obj', (object,), {
             'bytes_sent': 1000, 'bytes_recv': 2000,
             'packets_sent': 10, 'packets_recv': 20,
             'errin': 0, 'errout': 0,
             'dropin': 0, 'dropout': 0
         })):
        
        # Call the method directly
        await monitoring_agent._collect_system_metrics()
        
        # Check that metrics were stored
        assert len(monitoring_agent.metrics_history['cpu']) == 1
        assert len(monitoring_agent.metrics_history['memory']) == 1
        assert len(monitoring_agent.metrics_history['disk']) == 1
        assert len(monitoring_agent.metrics_history['network']) == 1
        
        # Check CPU metrics
        cpu_metrics = monitoring_agent.metrics_history['cpu'][0]
        assert cpu_metrics['cpu_percent'] == 25.5
        assert cpu_metrics['user'] == 10.1
        
        # Check memory metrics
        memory_metrics = monitoring_agent.metrics_history['memory'][0]
        assert memory_metrics['total'] == 8589934592
        assert memory_metrics['percent'] == 40.0
        
        # Check disk metrics
        disk_metrics = monitoring_agent.metrics_history['disk'][0]
        assert disk_metrics['mountpoint'] == '/'
        assert disk_metrics['percent'] == 50.0
        
        # Check network metrics
        net_metrics = monitoring_agent.metrics_history['network'][0]
        assert net_metrics['bytes_sent'] == 1000
        assert net_metrics['bytes_recv'] == 2000

@pytest.mark.asyncio
async def test_handle_metric_message(monitoring_agent):
    """Test handling of incoming metric messages"""
    # Create a test metric message
    test_metric = {
        'metric_type': 'custom_metric',
        'data': {
            'value': 42.0,
            'unit': 'requests/second',
            'timestamp': '2023-01-01T00:00:00.000000'
        },
        'threshold': 40.0
    }
    
    # Create a message with the test metric
    message = Message(
        header=MessageHeader(
            message_id="test-message-123",
            message_type=MessageType.METRIC,
            timestamp=datetime.utcnow().isoformat(),
            source_agent_id="test-agent-456",
            priority=MessagePriority.NORMAL
        ),
        payload=test_metric
    )
    
    # Process the message
    await monitoring_agent._handle_metric_message(message)
    
    # Check that the metric was stored
    assert 'custom_metric' in monitoring_agent.metrics_history
    assert len(monitoring_agent.metrics_history['custom_metric']) == 1
    assert monitoring_agent.metrics_history['custom_metric'][0]['value'] == 42.0
    
    # Check that an alert was triggered (value > threshold)
    monitoring_agent.broadcast.assert_called_once()
    _, kwargs = monitoring_agent.broadcast.call_args
    assert kwargs['message_type'] == MessageType.ALERT
    assert kwargs['severity'] == 'high'
    assert 'threshold exceeded' in kwargs['message']

@pytest.mark.asyncio
async def test_handle_get_metrics_command(monitoring_agent):
    """Test handling of get_metrics command"""
    # Add some test metrics
    monitoring_agent.metrics_history['cpu'] = [
        {'timestamp': '2023-01-01T00:00:00', 'value': 25.0},
        {'timestamp': '2023-01-01T00:01:00', 'value': 30.0},
    ]
    monitoring_agent.metrics_history['memory'] = [
        {'timestamp': '2023-01-01T00:00:00', 'value': 60.0},
    ]
    
    # Create a command message
    message = Message(
        header=MessageHeader(
            message_id="test-cmd-123",
            message_type=MessageType.COMMAND,
            timestamp=datetime.utcnow().isoformat(),
            source_agent_id="test-client-456",
            priority=MessagePriority.NORMAL
        ),
        payload={
            'command': 'get_metrics',
            'parameters': {
                'type': 'cpu',
                'limit': 1
            }
        }
    )
    
    # Process the command
    await monitoring_agent._handle_command(message)
    
    # Check that a response was sent
    monitoring_agent.send_message.assert_called_once()
    args, _ = monitoring_agent.send_message.call_args
    response = args[1]
    
    assert response.status == "success"
    assert 'metrics' in response.data
    assert 'cpu' in response.data['metrics']
    assert len(response.data['metrics']['cpu']) == 1  # Limited to 1 by the test
    assert response.data['metrics']['cpu'][0]['value'] == 30.0  # Most recent value

@pytest.mark.asyncio
async def test_handle_set_threshold_command(monitoring_agent):
    """Test handling of set_threshold command"""
    # Create a command message to update a threshold
    message = Message(
        header=MessageHeader(
            message_id="test-cmd-123",
            message_type=MessageType.COMMAND,
            timestamp=datetime.utcnow().isoformat(),
            source_agent_id="test-client-456",
            priority=MessagePriority.NORMAL
        ),
        payload={
            'command': 'set_threshold',
            'parameters': {
                'name': 'cpu_percent',
                'value': '85.0'
            }
        }
    )
    
    # Process the command
    await monitoring_agent._handle_command(message)
    
    # Check that a response was sent
    monitoring_agent.send_message.assert_called_once()
    args, _ = monitoring_agent.send_message.call_args
    response = args[1]
    
    # Verify the response
    assert response.status == "success"
    assert "thresholds" in response.data
    assert response.data["thresholds"]["cpu_percent"] == 85.0
    
    # Verify the threshold was actually updated
    assert monitoring_agent.thresholds["cpu_percent"] == 85.0

@pytest.mark.asyncio
async def test_trigger_alert(monitoring_agent):
    """Test alert triggering functionality"""
    # Test data
    alert_type = "high_cpu_usage"
    message = "CPU usage is above threshold"
    details = {
        'value': 95.5,
        'threshold': 90.0,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    # Trigger an alert
    await monitoring_agent._trigger_alert(alert_type, message, details)
    
    # Check that a broadcast was sent
    monitoring_agent.broadcast.assert_called_once()
    _, kwargs = monitoring_agent.broadcast.call_args
    
    # Verify the broadcast content
    assert kwargs['message_type'] == MessageType.ALERT
    assert kwargs['severity'] == 'high'
    assert kwargs['alert_type'] == alert_type
    assert message in kwargs['message']
    assert kwargs['details'] == details

@pytest.mark.asyncio
async def test_check_thresholds(monitoring_agent):
    """Test threshold checking functionality"""
    # Set up test thresholds
    monitoring_agent.thresholds = {
        'cpu_percent': 90.0,
        'memory_percent': 85.0,
        'disk_percent': 95.0
    }
    
    # Test metrics that should trigger alerts
    test_metrics = {
        'cpu': {'cpu_percent': 95.5},
        'memory': {'percent': 90.0},
        'disk': {'mountpoint': '/', 'percent': 96.0}
    }
    
    # Mock the _trigger_alert method
    with patch.object(monitoring_agent, '_trigger_alert') as mock_trigger_alert:
        # Check thresholds
        await monitoring_agent._check_thresholds(test_metrics)
        
        # Verify that _trigger_alert was called for each exceeded threshold
        assert mock_trigger_alert.call_count == 3
        
        # Check that the correct alert types were triggered
        alert_types = [call[0][0] for call in mock_trigger_alert.call_args_list]
        assert 'high_cpu_usage' in alert_types
        assert 'high_memory_usage' in alert_types
        assert 'high_disk_usage' in alert_types

@pytest.mark.asyncio
async def test_metrics_collection_loop(monitoring_agent):
    """Test the metrics collection loop"""
    # Set a shorter interval for testing
    monitoring_agent.metrics_interval = 0.1
    
    # Mock the _collect_system_metrics method
    with patch.object(monitoring_agent, '_collect_system_metrics') as mock_collect_metrics:
        # Start the metrics collection loop
        task = asyncio.create_task(monitoring_agent._collect_metrics_loop())
        
        # Let it run for a short time
        await asyncio.sleep(0.25)
        
        # Stop the loop
        monitoring_agent.running = False
        task.cancel()
        
        # Wait for the task to complete
        try:
            await task
        except asyncio.CancelledError:
            pass
        
        # Verify that _collect_system_metrics was called multiple times
        assert mock_collect_metrics.call_count >= 2

@pytest.mark.asyncio
async def test_get_status(monitoring_agent):
    """Test the get_status method"""
    # Add some test metrics
    monitoring_agent.metrics_history['cpu'] = [{'timestamp': '2023-01-01T00:00:00', 'value': 25.0}]
    monitoring_agent.metrics_history['memory'] = [{'timestamp': '2023-01-01T00:00:00', 'value': 60.0}]
    monitoring_agent.last_metrics_update = datetime.utcnow()
    
    # Get the status
    status = await monitoring_agent.get_status()
    
    # Verify the status content
    assert status['agent_id'] == str(monitoring_agent.id)
    assert status['name'] == "TestMonitor"
    assert status['status'] == AgentStatus.RUNNING
    assert 'metrics_collected' in status
    assert status['metrics_collected']['cpu'] == 1
    assert status['metrics_collected']['memory'] == 1
    assert 'thresholds' in status
    assert 'cpu_usage' in status
    assert 'memory_usage_mb' in status

@pytest.mark.asyncio
async def test_stop_method(monitoring_agent):
    """Test the stop method"""
    # Start the metrics collection loop
    monitoring_agent.metrics_task = asyncio.create_task(monitoring_agent._collect_metrics_loop())
    
    # Stop the agent
    await monitoring_agent.stop()
    
    # Verify that the metrics task was cancelled
    assert monitoring_agent.metrics_task.done()
    
    # Verify that the base stop method was called
    assert not monitoring_agent.running

if __name__ == "__main__":
    pytest.main(["-v", "test_monitoring_agent.py"])
