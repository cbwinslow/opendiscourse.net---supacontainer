#!/usr/bin/env python3
"""
Example demonstrating how to use the Supabase integration.

This script shows how to:
1. Initialize the AgentService
2. Register agent capabilities
3. Register agent resources
4. Record and query metrics
5. Check agent health
"""
import asyncio
import os
from uuid import uuid4
from datetime import datetime, timedelta

# Set up environment variables
os.environ["SUPABASE_URL"] = "your-supabase-url"
os.environ["SUPABASE_KEY"] = "your-supabase-key"

from ai_agents.services.agent_service import AgentService
from ai_agents.data.models import AgentCapabilities, AgentResources, AgentMetrics

async def main():
    print("=== Supabase Integration Example ===\n")
    
    # Initialize the service
    service = AgentService()
    
    # Generate a test agent ID
    agent_id = uuid4()
    print(f"Using test agent ID: {agent_id}\n")
    
    try:
        # 1. Register agent capabilities
        print("1. Registering agent capabilities...")
        capability = await service.create_capability(
            name="image_processing",
            description="Ability to process images using computer vision",
            parameters={"max_image_size": "10MB", "supported_formats": ["jpg", "png"]}
        )
        print(f"  - Created capability: {capability.name} (ID: {capability.id})")
        
        # 2. Register agent resources
        print("\n2. Registering agent resources...")
        gpu_resource = await service.register_resource(
            name="NVIDIA T4 GPU",
            resource_type="gpu",
            capacity=1.0,
            unit="count",
            description="NVIDIA T4 GPU with 16GB VRAM"
        )
        print(f"  - Registered resource: {gpu_resource.name} (Type: {gpu_resource.type})")
        
        # 3. Record some metrics
        print("\n3. Recording metrics...")
        for i in range(5):
            cpu_usage = 20 + i * 5  # Simulate increasing CPU usage
            await service.record_metric(
                agent_id=agent_id,
                name="cpu.usage",
                value=cpu_usage,
                tags={"unit": "percent", "source": "system"}
            )
            print(f"  - Recorded CPU usage: {cpu_usage}%")
        
        # 4. Query metrics
        print("\n4. Querying metrics...")
        metrics = await service.get_metric_history(
            agent_id=agent_id,
            metric_name="cpu.usage",
            time_window=timedelta(minutes=30)
        )
        print(f"  - Found {len(metrics)} metrics in the last 30 minutes")
        if metrics:
            print(f"  - Latest CPU usage: {metrics[0].value}% at {metrics[0].timestamp}")
        
        # 5. Check agent health
        print("\n5. Checking agent health...")
        health = await service.get_agent_health(agent_id)
        print(f"  - Agent healthy: {health['is_healthy']}")
        print(f"  - Last seen: {health['last_seen']}")
        
        # 6. Get resource utilization
        print("\n6. Checking resource utilization...")
        utilization = await service.get_resource_utilization()
        for resource_type, stats in utilization.items():
            print(f"  - {resource_type.upper()}:")
            print(f"    - Used: {stats['used']:.1f} {stats.get('unit', '')}")
            print(f"    - Total: {stats['total']:.1f} {stats.get('unit', '')}")
            print(f"    - Utilization: {stats['utilization']:.1f}%")
    
    except Exception as e:
        print(f"\nError: {str(e)}")
        import traceback
        traceback.print_exc()
    
    print("\n=== Example Complete ===")

if __name__ == "__main__":
    asyncio.run(main())
