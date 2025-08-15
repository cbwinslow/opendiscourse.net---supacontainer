import pytest
import asyncio
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch, MagicMock

from ..storage.redis_backend import RedisBackend
from ..data_models import (
    StorageConfig, StorageBackendType, Metric, Alert, AgentState, 
    MetricValue, AlertSeverity, AlertStatus, AgentStatus
)

# Test data
TEST_METRIC = Metric(
    id="test-metric-1",
    name="cpu.usage",
    type="gauge",
    values=[
        MetricValue(
            timestamp=datetime.utcnow(),
            value=75.5,
            tags={"host": "test-host"}
        )
    ]
)

TEST_ALERT = Alert(
    id="test-alert-1",
    name="High CPU Usage",
    description="CPU usage is above 90%",
    severity=AlertSeverity.WARNING,
    status=AlertStatus.FIRING,
    source="test-source",
    start_time=datetime.utcnow(),
    labels={"severity": "warning", "service": "test-service"}
)

TEST_AGENT_STATE = AgentState(
    id="test-agent-state-1",
    agent_id="test-agent-1",
    status=AgentStatus.RUNNING,
    metrics={"cpu": 10.5, "memory": 1024},
    last_heartbeat=datetime.utcnow()
)

@pytest.fixture
def redis_backend():
    config = StorageConfig(
        name="test-redis",
        backend_type=StorageBackendType.REDIS,
        connection_string="redis://localhost:6379/0",
        options={
            "metric_ttl_seconds": 86400,
            "alert_ttl_seconds": 172800,
            "agent_state_ttl_seconds": 3600
        }
    )
    return RedisBackend(config)

@pytest.fixture
def mock_redis():
    with patch('aioredis.Redis') as mock_redis_class:
        mock_redis = AsyncMock()
        mock_redis_class.return_value = mock_redis
        mock_redis.ping.return_value = True
        yield mock_redis

@pytest.mark.asyncio
async def test_connect_success(redis_backend, mock_redis):
    await redis_backend.connect()
    assert redis_backend.initialized is True
    assert redis_backend.redis is not None
    mock_redis.ping.assert_awaited_once()

@pytest.mark.asyncio
async def test_connect_failure(redis_backend):
    with patch('aioredis.Redis', side_effect=Exception("Connection failed")):
        with pytest.raises(Exception):
            await redis_backend.connect()
        assert redis_backend.initialized is False
        assert redis_backend.redis is None

@pytest.mark.asyncio
async def test_save_metric(redis_backend, mock_redis):
    await redis_backend.connect()
    mock_redis.set.return_value = True
    
    result = await redis_backend.save_metric(TEST_METRIC)
    
    assert result is True
    mock_redis.set.assert_awaited_once()
    args, kwargs = mock_redis.set.call_args
    assert "metric:test-metric-1" in args
    assert "cpu.usage" in kwargs["value"]
    assert kwargs["ex"] == 86400  # TTL from config

@pytest.mark.asyncio
async def test_get_metric(redis_backend, mock_redis):
    await redis_backend.connect()
    
    # Mock the Redis get response
    metric_data = {
        'id': 'test-metric-1',
        'name': 'cpu.usage',
        'type': 'gauge',
        'values': [{
            'timestamp': datetime.utcnow().isoformat(),
            'value': 75.5,
            'tags': {'host': 'test-host'}
        }],
        'created_at': datetime.utcnow().isoformat(),
        'updated_at': datetime.utcnow().isoformat()
    }
    mock_redis.get.return_value = json.dumps(metric_data)
    
    metric = await redis_backend.get_metric('test-metric-1')
    
    assert metric is not None
    assert metric.id == 'test-metric-1'
    assert metric.name == 'cpu.usage'
    assert len(metric.values) == 1
    assert metric.values[0].value == 75.5
    mock_redis.get.assert_awaited_once_with('metric:test-metric-1')

@pytest.mark.asyncio
async def test_save_alert(redis_backend, mock_redis):
    await redis_backend.connect()
    mock_redis.set.return_value = True
    
    result = await redis_backend.save_alert(TEST_ALERT)
    
    assert result is True
    mock_redis.set.assert_awaited_once()
    args, kwargs = mock_redis.set.call_args
    assert "alert:test-alert-1" in args
    assert "High CPU Usage" in kwargs["value"]
    assert kwargs["ex"] == 172800  # TTL from config

@pytest.mark.asyncio
async def test_save_agent_state(redis_backend, mock_redis):
    await redis_backend.connect()
    mock_redis.set.return_value = True
    
    result = await redis_backend.save_agent_state(TEST_AGENT_STATE)
    
    assert result is True
    mock_redis.set.assert_awaited_once()
    args, kwargs = mock_redis.set.call_args
    assert "agent:test-agent-1" in args
    assert "test-agent-state-1" in kwargs["value"]
    assert kwargs["ex"] == 3600  # TTL from config

@pytest.mark.asyncio
async def test_close(redis_backend, mock_redis):
    await redis_backend.connect()
    await redis_backend.close()
    
    assert redis_backend.initialized is False
    assert redis_backend.redis is None
    assert redis_backend.pool is None
    mock_redis.close.assert_awaited_once()

@pytest.mark.asyncio
async def test_get_database_stats(redis_backend, mock_redis):
    await redis_backend.connect()
    
    # Mock Redis info response
    mock_redis.info.return_value = {
        'redis_version': '6.2.5',
        'uptime_in_seconds': 12345,
        'connected_clients': 5,
        'used_memory_human': '1.2M',
        'total_commands_processed': 1000
    }
    
    stats = await redis_backend.get_database_stats()
    
    assert stats['backend'] == 'Redis'
    assert stats['version'] == '6.2.5'
    assert stats['connected_clients'] == 5
    assert '1.2M' in stats['used_memory']
    mock_redis.info.assert_awaited_once()
