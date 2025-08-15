import asyncio
import aio_pika
import json
import logging
from typing import Dict, Any, Optional, Callable, Awaitable, List
from uuid import UUID, uuid4

from ..schemas.messages import Message, MessageHeader, MessageType, MessagePriority

class RabbitMQClient:
    """Asynchronous RabbitMQ client for message queue communication"""
    
    def __init__(
        self,
        amqp_url: str = "amqp://guest:guest@localhost/",
        exchange_name: str = "ai_agents",
        queue_name: str = None,
        reconnect_interval: int = 5,
        max_retries: int = 5
    ):
        """Initialize the RabbitMQ client
        
        Args:
            amqp_url: URL to connect to RabbitMQ
            exchange_name: Name of the exchange to use
            queue_name: Name of the queue to consume from (if None, a random name will be generated)
            reconnect_interval: Seconds to wait between reconnection attempts
            max_retries: Maximum number of connection retry attempts
        """
        self.amqp_url = amqp_url
        self.exchange_name = exchange_name
        self.queue_name = queue_name or f"agent_queue_{uuid4().hex[:8]}"
        self.reconnect_interval = reconnect_interval
        self.max_retries = max_retries
        
        self.connection = None
        self.channel = None
        self.exchange = None
        self.queue = None
        self._consuming = False
        self._message_handler = None
        self._reconnect_task = None
        self._connection_lock = asyncio.Lock()
        self._consumers = {}
        self.logger = logging.getLogger(__name__)
    
    async def connect(self) -> bool:
        """Establish connection to RabbitMQ server
        
        Returns:
            bool: True if connection was successful, False otherwise
        """
        if self.connection and not self.connection.is_closed:
            return True
            
        async with self._connection_lock:
            if self.connection and not self.connection.is_closed:
                return True
                
            retries = 0
            last_error = None
            
            while retries < self.max_retries:
                try:
                    self.logger.info(f"Connecting to RabbitMQ at {self.amqp_url} (attempt {retries + 1}/{self.max_retries})")
                    self.connection = await aio_pika.connect_robust(
                        self.amqp_url,
                        client_properties={
                            "connection_name": f"ai_agent_{self.queue_name}"
                        }
                    )
                    
                    # Set up connection closed callback
                    self.connection.add_close_callback(self._on_connection_closed)
                    
                    # Create channel
                    self.channel = await self.connection.channel()
                    
                    # Declare the exchange
                    self.exchange = await self.channel.declare_exchange(
                        self.exchange_name,
                        aio_pika.ExchangeType.TOPIC,
                        durable=True,
                        auto_delete=False
                    )
                    
                    # Declare the queue
                    self.queue = await self.channel.declare_queue(
                        self.queue_name,
                        durable=True,
                        auto_delete=False,
                        arguments={
                            'x-message-ttl': 86400000,  # 24 hours in ms
                            'x-max-length': 10000,      # Max messages in queue
                        }
                    )
                    
                    self.logger.info(f"Connected to RabbitMQ and set up exchange '{self.exchange_name}' and queue '{self.queue_name}'")
                    return True
                    
                except Exception as e:
                    last_error = e
                    retries += 1
                    self.logger.error(f"Failed to connect to RabbitMQ (attempt {retries}/{self.max_retries}): {str(e)}")
                    
                    if retries < self.max_retries:
                        await asyncio.sleep(self.reconnect_interval)
            
            self.logger.error(f"Failed to connect to RabbitMQ after {self.max_retries} attempts: {str(last_error)}")
            return False
    
    def _on_connection_closed(self, connection, exception=None):
        """Called when the connection to RabbitMQ is closed unexpectedly"""
        self.logger.warning(f"RabbitMQ connection closed: {str(exception) if exception else 'No error provided'}")
        self._schedule_reconnect()
    
    def _schedule_reconnect(self):
        """Schedule a reconnection attempt"""
        if self._reconnect_task is None or self._reconnect_task.done():
            self.logger.info(f"Scheduling reconnection in {self.reconnect_interval} seconds...")
            self._reconnect_task = asyncio.create_task(self._reconnect())
    
    async def _reconnect(self):
        """Attempt to reconnect to RabbitMQ"""
        try:
            await asyncio.sleep(self.reconnect_interval)
            await self.connect()
            
            # Re-register all consumers
            for routing_key, handler in list(self._consumers.items()):
                await self.consume(routing_key, handler)
                
        except Exception as e:
            self.logger.error(f"Reconnection attempt failed: {str(e)}")
            self._schedule_reconnect()
    
    async def publish(
        self,
        message: Message,
        routing_key: str = None,
        persistent: bool = True,
        priority: int = None
    ) -> bool:
        """Publish a message to the exchange
        
        Args:
            message: The message to publish
            routing_key: Routing key for the message (default: message type)
            persistent: Whether the message should be persisted to disk
            priority: Message priority (0-9)
            
        Returns:
            bool: True if the message was published successfully, False otherwise
        """
        if not self.connection or self.connection.is_closed:
            if not await self.connect():
                self.logger.error("Cannot publish message: Not connected to RabbitMQ")
                return False
        
        try:
            # Use message type as routing key if not specified
            if routing_key is None:
                routing_key = message.header.message_type.value
            
            # Convert message to JSON
            message_data = message.model_dump_json()
            
            # Create message properties
            properties = aio_pika.MessageProperties(
                content_type="application/json",
                delivery_mode=2 if persistent else 1,  # 2 = persistent, 1 = transient
                priority=priority or message.header.priority.value if isinstance(message.header.priority, MessagePriority) else 0,
                message_id=str(message.header.message_id),
                correlation_id=str(message.header.correlation_id) if message.header.correlation_id else None,
                timestamp=message.header.timestamp,
                headers={
                    'agent_id': str(message.header.source_agent_id),
                    'message_type': message.header.message_type.value,
                    'priority': message.header.priority.value if isinstance(message.header.priority, MessagePriority) else 0
                }
            )
            
            # Publish the message
            await self.exchange.publish(
                aio_pika.Message(
                    body=message_data.encode(),
                    properties=properties
                ),
                routing_key=routing_key
            )
            
            self.logger.debug(f"Published message to {routing_key}: {message.header.message_type}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to publish message: {str(e)}", exc_info=True)
            return False
    
    async def consume(
        self,
        routing_key: str,
        callback: Callable[[Message], Awaitable[None]],
        queue_name: str = None,
        auto_ack: bool = False
    ) -> bool:
        """Consume messages from the queue
        
        Args:
            routing_key: Routing key to bind the queue to
            callback: Async function to call when a message is received
            queue_name: Name of the queue to consume from (default: use instance queue)
            auto_ack: Whether to automatically acknowledge messages
            
        Returns:
            bool: True if the consumer was started successfully, False otherwise
        """
        if not self.connection or self.connection.is_closed:
            if not await self.connect():
                self.logger.error("Cannot start consumer: Not connected to RabbitMQ")
                return False
        
        try:
            queue = self.queue
            
            # If a different queue name is provided, declare it
            if queue_name and queue_name != self.queue_name:
                queue = await self.channel.declare_queue(
                    queue_name,
                    durable=True,
                    auto_delete=False,
                    arguments={
                        'x-message-ttl': 86400000,  # 24 hours in ms
                        'x-max-length': 10000,      # Max messages in queue
                    }
                )
            
            # Bind the queue to the exchange with the routing key
            await queue.bind(self.exchange, routing_key=routing_key)
            
            # Store the consumer
            self._consumers[routing_key] = callback
            
            # Start consuming
            await queue.consume(
                lambda message: self._on_message(message, callback, auto_ack),
                no_ack=auto_ack
            )
            
            self.logger.info(f"Started consuming messages with routing key: {routing_key}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to start consumer: {str(e)}", exc_info=True)
            return False
    
    async def _on_message(self, message: aio_pika.IncomingMessage, callback: Callable, auto_ack: bool):
        """Handle an incoming message"""
        try:
            # Parse the message
            body = message.body.decode()
            
            try:
                message_data = json.loads(body)
                msg = Message(**message_data)
            except Exception as e:
                self.logger.error(f"Failed to parse message: {str(e)}")
                if not auto_ack:
                    await message.nack(requeue=False)
                return
            
            # Process the message
            try:
                await callback(msg)
                
                # Acknowledge the message if auto_ack is False
                if not auto_ack:
                    await message.ack()
                    
            except Exception as e:
                self.logger.error(f"Error processing message: {str(e)}", exc_info=True)
                
                # Nack the message with requeue based on retry count
                if not auto_ack:
                    retry_count = message.headers.get('x-retry-count', 0) if message.headers else 0
                    
                    if retry_count < 3:  # Max 3 retries
                        await message.nack(requeue=True)
                        
                        # Update retry count
                        if message.headers is None:
                            message.headers = {}
                        message.headers['x-retry-count'] = retry_count + 1
                    else:
                        await message.nack(requeue=False)
                        self.logger.error(f"Message {message.message_id} failed after 3 retries")
            
        except Exception as e:
            self.logger.error(f"Unexpected error in message handler: {str(e)}", exc_info=True)
    
    async def close(self):
        """Close the connection to RabbitMQ"""
        try:
            if self._reconnect_task and not self._reconnect_task.done():
                self._reconnect_task.cancel()
                try:
                    await self._reconnect_task
                except asyncio.CancelledError:
                    pass
                
            if self.connection and not self.connection.is_closed:
                await self.connection.close()
                self.logger.info("Closed RabbitMQ connection")
                
        except Exception as e:
            self.logger.error(f"Error closing RabbitMQ connection: {str(e)}", exc_info=True)
        finally:
            self.connection = None
            self.channel = None
            self.exchange = None
            self.queue = None
    
    async def __aenter__(self):
        await self.connect()
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()


class RabbitMQManager:
    """Singleton manager for RabbitMQ connections"""
    _instance = None
    _clients: Dict[str, RabbitMQClient] = {}
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super(RabbitMQManager, cls).__new__(cls)
        return cls._instance
    
    @classmethod
    async def get_client(
        cls,
        name: str = "default",
        amqp_url: str = "amqp://guest:guest@localhost/",
        exchange_name: str = "ai_agents",
        queue_name: str = None
    ) -> RabbitMQClient:
        """Get or create a RabbitMQ client instance"""
        if name not in cls._clients:
            client = RabbitMQClient(
                amqp_url=amqp_url,
                exchange_name=exchange_name,
                queue_name=queue_name
            )
            await client.connect()
            cls._clients[name] = client
            
        return cls._clients[name]
    
    @classmethod
    async def close_all(cls):
        """Close all RabbitMQ connections"""
        for name, client in list(cls._clients.items()):
            try:
                await client.close()
                del cls._clients[name]
            except Exception as e:
                logging.getLogger(__name__).error(f"Error closing RabbitMQ client '{name}': {str(e)}", exc_info=True)


# Example usage:
# async def message_handler(message: Message):
#     print(f"Received message: {message}")
# 
# async def main():
#     # Get a RabbitMQ client
#     client = await RabbitMQManager.get_client(
#         name="monitoring_agent",
#         amqp_url="amqp://guest:guest@localhost/",
#         exchange_name="ai_agents",
#         queue_name="monitoring_agent_queue"
#     )
#     
#     # Start consuming messages
#     await client.consume("monitoring.#", message_handler)
#     
#     # Publish a message
#     message = Message(
#         header=MessageHeader(
#             message_id=uuid4(),
#             message_type=MessageType.COMMAND,
#             source_agent_id=uuid4(),
#             timestamp=datetime.utcnow().isoformat(),
#             priority=MessagePriority.NORMAL
#         ),
#         payload={
#             "command": "get_metrics",
#             "parameters": {
#                 "type": "cpu",
#                 "limit": 10
#             }
#         }
#     )
#     
#     await client.publish(message, routing_key="monitoring.commands")
#     
#     # Keep the consumer running
#     while True:
#         await asyncio.sleep(1)
# 
# if __name__ == "__main__":
#     asyncio.run(main())
