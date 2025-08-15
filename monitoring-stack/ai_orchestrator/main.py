import asyncio
import json
import logging
import os
from typing import Dict, Any, List, Optional
from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.security import APIKeyHeader
import pika
from pika.adapters.blocking_connection import BlockingChannel
from pika.spec import BasicProperties
from schemas.messages import (
    MessageType, BaseMessage, MetricMessage, LogMessage, 
    AlertMessage, CommandMessage, ResponseMessage, ResponseStatus
)
from opensearchpy import OpenSearch, helpers
import httpx
import prometheus_client as prom
from datetime import datetime, timedelta
import croniter
from prometheus_client import Counter, Gauge, Histogram

# Initialize FastAPI
app = FastAPI(title="AI Orchestrator", version="1.0.0")

# Metrics
MESSAGES_RECEIVED = Counter(
    'ai_orchestrator_messages_received_total',
    'Total number of messages received',
    ['message_type']
)
MESSAGES_PROCESSED = Counter(
    'ai_orchestrator_messages_processed_total',
    'Total number of messages processed',
    ['message_type', 'status']
)
MESSAGE_PROCESSING_TIME = Histogram(
    'ai_orchestrator_message_processing_seconds',
    'Time spent processing messages',
    ['message_type']
)
ACTIVE_AGENTS = Gauge(
    'ai_orchestrator_active_agents',
    'Number of active agents registered'
)

# Configuration
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/")
OPENSEARCH_URL = os.getenv("OPENSEARCH_URL", "http://localhost:9200")
LOKI_URL = os.getenv("LOKI_URL", "http://localhost:3100")
API_KEY = os.getenv("AI_ORCHESTRATOR_API_KEY")

# Security
api_key_header = APIKeyHeader(name="X-API-Key")

def get_api_key(api_key: str = Depends(api_key_header)) -> str:
    if api_key != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid API Key"
        )
    return api_key

class AIOrchestrator:
    def __init__(self):
        self.rabbit_conn = None
        self.channel = None
        self.opensearch = None
        self.agents = {}
        self.scheduled_tasks = []
        self.logger = self._setup_logger()
        
    def _setup_logger(self):
        logger = logging.getLogger("ai_orchestrator")
        logger.setLevel(logging.INFO)
        handler = logging.StreamHandler()
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        return logger
    
    async def connect(self):
        """Initialize connections to RabbitMQ and OpenSearch"""
        self._connect_rabbitmq()
        self._connect_opensearch()
        await self._load_agents()
        self._start_scheduled_tasks()
    
    def _connect_rabbitmq(self):
        """Establish connection to RabbitMQ"""
        try:
            self.rabbit_conn = pika.BlockingConnection(pika.URLParameters(RABBITMQ_URL))
            self.channel = self.rabbit_conn.channel()
            
            # Declare exchanges and queues
            self.channel.exchange_declare(exchange='orchestrator', exchange_type='topic', durable=True)
            self.channel.queue_declare(queue='orchestrator.commands', durable=True)
            self.channel.queue_bind(exchange='orchestrator', queue='orchestrator.commands', routing_key='command.*')
            
            # Set up consumer
            self.channel.basic_consume(queue='orchestrator.commands', on_message_callback=self._on_message, auto_ack=False)
            self.logger.info("Connected to RabbitMQ")
        except Exception as e:
            self.logger.error(f"Failed to connect to RabbitMQ: {e}")
            raise
    
    def _connect_opensearch(self):
        """Initialize OpenSearch connection"""
        try:
            self.opensearch = OpenSearch([OPENSEARCH_URL], verify_certs=False, ssl_show_warn=False)
            if not self.opensearch.ping():
                raise ConnectionError("Could not connect to OpenSearch")
            self._ensure_indices()
            self.logger.info("Connected to OpenSearch")
        except Exception as e:
            self.logger.error(f"Failed to connect to OpenSearch: {e}")
            raise
    
    def _ensure_indices(self):
        """Ensure required indices exist in OpenSearch"""
        indices = {
            "messages": {
                "mappings": {
                    "properties": {
                        "timestamp": {"type": "date"},
                        "message_type": {"type": "keyword"},
                        "source": {"type": "keyword"},
                        "severity": {"type": "keyword"},
                        "correlation_id": {"type": "keyword"},
                        "content": {"type": "object", "enabled": True}
                    }
                }
            },
            "agents": {
                "mappings": {
                    "properties": {
                        "name": {"type": "keyword"},
                        "type": {"type": "keyword"},
                        "status": {"type": "keyword"},
                        "last_heartbeat": {"type": "date"},
                        "capabilities": {"type": "keyword"},
                        "metadata": {"type": "object", "enabled": True}
                    }
                }
            }
        }
        
        for index_name, index_body in indices.items():
            if not self.opensearch.indices.exists(index=index_name):
                self.opensearch.indices.create(index=index_name, body=index_body)
    
    async def _load_agents(self):
        """Load registered agents from OpenSearch"""
        try:
            result = self.opensearch.search(
                index="agents",
                body={"query": {"match_all": {}}},
                size=1000
            )
            self.agents = {
                hit["_source"]["name"]: hit["_source"] 
                for hit in result.get("hits", {}).get("hits", [])
            }
            ACTIVE_AGENTS.set(len(self.agents))
            self.logger.info(f"Loaded {len(self.agents)} agents from OpenSearch")
        except Exception as e:
            self.logger.error(f"Failed to load agents: {e}")
    
    def _start_scheduled_tasks(self):
        """Start background tasks for scheduled operations"""
        # Schedule agent health checks every 30 seconds
        self._schedule_task("*/30 * * * * *", self._check_agent_health)
        
        # Schedule metrics collection every minute
        self._schedule_task("0 * * * * *", self._collect_system_metrics)
        
        self.logger.info(f"Started {len(self.scheduled_tasks)} scheduled tasks")
    
    def _schedule_task(self, cron_expression: str, func):
        """Helper to schedule a function to run on a cron schedule"""
        cron = croniter.croniter(cron_expression)
        next_run = cron.get_next(datetime)
        self.scheduled_tasks.append({
            "cron": cron_expression,
            "func": func,
            "next_run": next_run
        })
    
    async def _check_agent_health(self):
        """Check health of all registered agents"""
        now = datetime.utcnow()
        for agent_name, agent in list(self.agents.items()):
            last_heartbeat = agent.get("last_heartbeat")
            if not last_heartbeat or (now - last_heartbeat) > timedelta(minutes=5):
                self.logger.warning(f"Agent {agent_name} is not responding")
                # TODO: Take action for unresponsive agents
    
    async def _collect_system_metrics(self):
        """Collect and store system metrics"""
        # TODO: Implement actual system metrics collection
        pass
    
    def _on_message(self, ch: BlockingChannel, method, properties: BasicProperties, body: bytes):
        """Handle incoming messages from RabbitMQ"""
        try:
            message = json.loads(body)
            message_type = message.get("message_type")
            
            # Update metrics
            MESSAGES_RECEIVED.labels(message_type=message_type).inc()
            
            with MESSAGE_PROCESSING_TIME.labels(message_type=message_type).time():
                # Process message based on type
                if message_type == MessageType.METRIC:
                    self._handle_metric(message)
                elif message_type == MessageType.LOG:
                    self._handle_log(message)
                elif message_type == MessageType.ALERT:
                    self._handle_alert(message)
                elif message_type == MessageType.COMMAND:
                    self._handle_command(message)
                elif message_type == MessageType.RESPONSE:
                    self._handle_response(message)
                else:
                    self.logger.warning(f"Unknown message type: {message_type}")
                    ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
                    return
                
                # Acknowledge message
                ch.basic_ack(delivery_tag=method.delivery_tag)
                MESSAGES_PROCESSED.labels(
                    message_type=message_type, 
                    status="success"
                ).inc()
                
        except json.JSONDecodeError as e:
            self.logger.error(f"Failed to decode message: {e}")
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        except Exception as e:
            self.logger.error(f"Error processing message: {e}", exc_info=True)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
            MESSAGES_PROCESSED.labels(
                message_type=message_type or "unknown", 
                status="error"
            ).inc()
    
    def _handle_metric(self, message: Dict[str, Any]):
        """Handle metric messages"""
        # Store in OpenSearch
        self.opensearch.index(
            index="messages",
            body={
                "@timestamp": datetime.utcnow().isoformat(),
                **message
            }
        )
        
        # TODO: Check against alert rules
        
    def _handle_log(self, message: Dict[str, Any]):
        """Handle log messages"""
        # Forward to Loki
        log_entry = {
            "streams": [{
                "stream": {"source": message.get("source", "unknown")},
                "values": [
                    [str(int(datetime.utcnow().timestamp() * 1e9)), 
                     json.dumps(message)]
                ]
            }]
        }
        
        try:
            response = httpx.post(
                f"{LOKI_URL}/loki/api/v1/push",
                json=log_entry,
                timeout=5.0
            )
            response.raise_for_status()
        except Exception as e:
            self.logger.error(f"Failed to send logs to Loki: {e}")
    
    def _handle_alert(self, message: Dict[str, Any]):
        """Handle alert messages"""
        # Store in OpenSearch
        self.opensearch.index(
            index="alerts",
            body={
                "@timestamp": datetime.utcnow().isoformat(),
                **message
            }
        )
        
        # TODO: Notify appropriate channels (Slack, Email, etc.)
        self.logger.warning(f"ALERT: {message.get('alert_name')} - {message.get('message', 'No message')}")
    
    def _handle_command(self, message: Dict[str, Any]):
        """Handle command messages"""
        # TODO: Implement command handling logic
        pass
    
    def _handle_response(self, message: Dict[str, Any]):
        """Handle response messages"""
        # TODO: Implement response handling logic
        pass
    
    async def process_scheduled_tasks(self):
        """Process all scheduled tasks that are due"""
        now = datetime.utcnow()
        for task in self.scheduled_tasks:
            if now >= task["next_run"]:
                try:
                    if asyncio.iscoroutinefunction(task["func"]):
                        await task["func"]()
                    else:
                        loop = asyncio.get_event_loop()
                        await loop.run_in_executor(None, task["func"])
                except Exception as e:
                    self.logger.error(f"Error in scheduled task {task['func'].__name__}: {e}")
                
                # Schedule next run
                cron = croniter.croniter(task["cron"], now)
                task["next_run"] = cron.get_next(datetime)
    
    async def run(self):
        """Main run loop"""
        self.logger.info("Starting AI Orchestrator")
        await self.connect()
        
        try:
            while True:
                # Process scheduled tasks
                await self.process_scheduled_tasks()
                
                # Process RabbitMQ messages with a timeout
                self.rabbit_conn.process_data_events(time_limit=1.0)
                
                # Small sleep to prevent tight loop
                await asyncio.sleep(0.1)
                
        except KeyboardInterrupt:
            self.logger.info("Shutting down...")
        except Exception as e:
            self.logger.error(f"Error in main loop: {e}", exc_info=True)
        finally:
            if self.rabbit_conn and self.rabbit_conn.is_open:
                self.rabbit_conn.close()
            self.logger.info("Shutdown complete")

# FastAPI Endpoints
@app.get("/health")
async def health_check():
    return {"status": "healthy"}

@app.get("/metrics")
async def metrics():
    return prom.generate_latest()

# Initialize and run the orchestrator
orchestrator = AIOrchestrator()

@app.on_event("startup")
async def startup_event():
    """Start the orchestrator when the FastAPI app starts"""
    asyncio.create_task(orchestrator.run())

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
