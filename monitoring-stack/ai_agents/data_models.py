from datetime import datetime
from enum import Enum
from typing import List, Dict, Any, Optional, Union
from pydantic import BaseModel, Field, validator, root_validator
from uuid import UUID, uuid4

# Enums for consistent values
class MetricType(str, Enum):
    CPU = "cpu"
    MEMORY = "memory"
    DISK = "disk"
    NETWORK = "network"
    CUSTOM = "custom"

class AlertSeverity(str, Enum):
    INFO = "info"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class StorageType(str, Enum):
    SQL = "sql"
    VECTOR = "vector"
    TIMESERIES = "timeseries"

# Base models
class BaseDataModel(BaseModel):
    """Base model with common fields and methods"""
    id: UUID = Field(default_factory=uuid4)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat(),
            UUID: lambda v: str(v)
        }
    
    @root_validator(pre=True)
    def set_updated_at(cls, values):
        if 'updated_at' not in values:
            values['updated_at'] = datetime.utcnow()
        return values

# Metric Models
class MetricValue(BaseModel):
    """Represents a single metric value with timestamp"""
    timestamp: datetime
    value: float
    tags: Dict[str, str] = Field(default_factory=dict)
    
    class Config:
        json_encoders = {
            datetime: lambda v: v.isoformat()
        }

class Metric(BaseDataModel):
    """Represents a metric with a series of values"""
    name: str
    type: MetricType
    description: Optional[str] = None
    unit: Optional[str] = None
    values: List[MetricValue] = Field(default_factory=list)
    
    def add_value(self, value: float, timestamp: datetime = None, tags: Dict[str, str] = None):
        """Add a new value to the metric"""
        if timestamp is None:
            timestamp = datetime.utcnow()
        if tags is None:
            tags = {}
            
        self.values.append(MetricValue(
            timestamp=timestamp,
            value=value,
            tags=tags
        ))
        self.updated_at = datetime.utcnow()
        
        # Keep values sorted by timestamp
        self.values.sort(key=lambda x: x.timestamp)
        
        return self

# Alert Models
class Alert(BaseDataModel):
    """Represents an alert condition or event"""
    name: str
    description: str
    severity: AlertSeverity
    source: str
    status: str = "active"  # active, acknowledged, resolved, suppressed
    start_time: datetime = Field(default_factory=datetime.utcnow)
    end_time: Optional[datetime] = None
    acknowledged_by: Optional[str] = None
    acknowledged_at: Optional[datetime] = None
    resolved_by: Optional[str] = None
    resolved_at: Optional[datetime] = None
    labels: Dict[str, str] = Field(default_factory=dict)
    annotations: Dict[str, str] = Field(default_factory=dict)
    
    def acknowledge(self, user: str):
        """Mark the alert as acknowledged"""
        self.status = "acknowledged"
        self.acknowledged_by = user
        self.acknowledged_at = datetime.utcnow()
        self.updated_at = datetime.utcnow()
    
    def resolve(self, user: str):
        """Mark the alert as resolved"""
        self.status = "resolved"
        self.resolved_by = user
        self.resolved_at = datetime.utcnow()
        self.end_time = datetime.utcnow()
        self.updated_at = datetime.utcnow()

# Agent State Models
class AgentState(BaseDataModel):
    """Represents the state of an agent at a point in time"""
    agent_id: UUID
    status: str  # running, stopped, error, etc.
    metrics: Dict[str, Any] = Field(default_factory=dict)
    last_heartbeat: Optional[datetime] = None
    
    @validator('last_heartbeat', pre=True, always=True)
    def set_last_heartbeat(cls, v):
        return v or datetime.utcnow()

# Storage Models
class StorageConfig(BaseModel):
    """Configuration for a storage backend"""
    type: StorageType
    connection_string: str
    table_name: Optional[str] = None
    collection_name: Optional[str] = None
    options: Dict[str, Any] = Field(default_factory=dict)

class QueryFilter(BaseModel):
    """Filter for querying data"""
    field: str
    operator: str  # =, !=, >, <, >=, <=, in, not_in, contains, etc.
    value: Any

class QueryOptions(BaseModel):
    """Options for querying data"""
    filters: List[QueryFilter] = Field(default_factory=list)
    limit: Optional[int] = 100
    offset: Optional[int] = 0
    sort_by: Optional[str] = None
    sort_order: str = "desc"  # asc or desc

# Database Schema Models
class DatabaseSchema(BaseModel):
    """Represents the database schema for the monitoring system"""
    version: str
    tables: Dict[str, Dict[str, str]]  # table_name -> {column_name: column_type}
    indexes: Dict[str, List[str]]  # table_name -> [index_definition]
    
    def get_create_table_sql(self, table_name: str) -> str:
        """Generate SQL to create a table"""
        if table_name not in self.tables:
            raise ValueError(f"Table {table_name} not found in schema")
        
        columns = [f"id UUID PRIMARY KEY"]
        for col_name, col_type in self.tables[table_name].items():
            if col_name != "id":
                columns.append(f"{col_name} {col_type}")
        
        # Add created_at and updated_at timestamps
        columns.extend([
            "created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP",
            "updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP"
        ])
        
        # Add indexes
        index_sql = ""
        for idx_def in self.indexes.get(table_name, []):
            index_sql += f"CREATE INDEX IF NOT EXISTS idx_{table_name}_{idx_def} ON {table_name}({idx_def});\n"
        
        return f"""
        CREATE TABLE IF NOT EXISTS {table_name} (
            {', '.join(columns)}
        );
        
        -- Create update trigger for updated_at
        CREATE OR REPLACE FUNCTION update_updated_at_column()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
        
        DROP TRIGGER IF EXISTS update_{table_name}_updated_at ON {table_name};
        CREATE TRIGGER update_{table_name}_updated_at
        BEFORE UPDATE ON {table_name}
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
        
        {index_sql}
        """

# Define the database schema
MONITORING_SCHEMA = DatabaseSchema(
    version="1.0.0",
    tables={
        "metrics": {
            "name": "VARCHAR(255) NOT NULL",
            "type": "VARCHAR(50) NOT NULL",
            "description": "TEXT",
            "unit": "VARCHAR(50)",
            "values": "JSONB NOT NULL DEFAULT '[]'::jsonb",
            "metadata": "JSONB NOT NULL DEFAULT '{}'::jsonb"
        },
        "alerts": {
            "name": "VARCHAR(255) NOT NULL",
            "description": "TEXT",
            "severity": "VARCHAR(20) NOT NULL",
            "source": "VARCHAR(255) NOT NULL",
            "status": "VARCHAR(20) NOT NULL",
            "start_time": "TIMESTAMP WITH TIME ZONE NOT NULL",
            "end_time": "TIMESTAMP WITH TIME ZONE",
            "acknowledged_by": "VARCHAR(255)",
            "acknowledged_at": "TIMESTAMP WITH TIME ZONE",
            "resolved_by": "VARCHAR(255)",
            "resolved_at": "TIMESTAMP WITH TIME ZONE",
            "labels": "JSONB NOT NULL DEFAULT '{}'::jsonb",
            "annotations": "JSONB NOT NULL DEFAULT '{}'::jsonb"
        },
        "agent_states": {
            "agent_id": "UUID NOT NULL",
            "status": "VARCHAR(50) NOT NULL",
            "metrics": "JSONB NOT NULL DEFAULT '{}'::jsonb",
            "last_heartbeat": "TIMESTAMP WITH TIME ZONE"
        }
    },
    indexes={
        "metrics": ["name", "type", "(metadata->>'host')"],
        "alerts": ["severity", "status", "start_time", "source"],
        "agent_states": ["agent_id", "status", "last_heartbeat"]
    }
)

# Storage Adapter Base Class
class StorageAdapter:
    """Base class for storage adapters"""
    
    def __init__(self, config: StorageConfig):
        self.config = config
    
    async def connect(self):
        """Connect to the storage backend"""
        raise NotImplementedError
    
    async def disconnect(self):
        """Disconnect from the storage backend"""
        raise NotImplementedError
    
    async def save_metric(self, metric: Metric) -> bool:
        """Save a metric to storage"""
        raise NotImplementedError
    
    async def get_metric(self, metric_id: UUID) -> Optional[Metric]:
        """Get a metric by ID"""
        raise NotImplementedError
    
    async def query_metrics(
        self,
        name: str = None,
        metric_type: MetricType = None,
        start_time: datetime = None,
        end_time: datetime = None,
        tags: Dict[str, str] = None,
        options: QueryOptions = None
    ) -> List[Metric]:
        """Query metrics with filters"""
        raise NotImplementedError
    
    async def save_alert(self, alert: Alert) -> bool:
        """Save an alert to storage"""
        raise NotImplementedError
    
    async def get_alert(self, alert_id: UUID) -> Optional[Alert]:
        """Get an alert by ID"""
        raise NotImplementedError
    
    async def query_alerts(
        self,
        status: str = None,
        severity: AlertSeverity = None,
        source: str = None,
        start_time: datetime = None,
        end_time: datetime = None,
        labels: Dict[str, str] = None,
        options: QueryOptions = None
    ) -> List[Alert]:
        """Query alerts with filters"""
        raise NotImplementedError
    
    async def save_agent_state(self, state: AgentState) -> bool:
        """Save an agent state to storage"""
        raise NotImplementedError
    
    async def get_agent_state(self, agent_id: UUID) -> Optional[AgentState]:
        """Get the latest state for an agent"""
        raise NotImplementedError
    
    async def get_agent_states(
        self,
        status: str = None,
        last_heartbeat_after: datetime = None,
        options: QueryOptions = None
    ) -> List[AgentState]:
        """Query agent states with filters"""
        raise NotImplementedError

# Example usage of the data models
if __name__ == "__main__":
    # Create a metric
    cpu_metric = Metric(
        name="cpu.usage",
        type=MetricType.CPU,
        description="CPU usage percentage",
        unit="percent"
    )
    
    # Add some values
    cpu_metric.add_value(25.5, tags={"host": "server1", "core": "0"})
    cpu_metric.add_value(30.2, tags={"host": "server1", "core": "1"})
    
    # Create an alert
    alert = Alert(
        name="High CPU Usage",
        description="CPU usage is above 90%",
        severity=AlertSeverity.HIGH,
        source="monitoring_agent",
        labels={"host": "server1", "severity": "high"},
        annotations={"summary": "High CPU usage on server1", "runbook": "Check for runaway processes"}
    )
    
    # Acknowledge the alert
    alert.acknowledge("admin@example.com")
    
    # Print the models
    print("Metric:", cpu_metric.model_dump_json(indent=2))
    print("\nAlert:", alert.model_dump_json(indent=2))
    
    # Generate SQL for the schema
    print("\nSQL for metrics table:")
    print(MONITORING_SCHEMA.get_create_table_sql("metrics"))
