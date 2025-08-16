""
End-to-end tests for OpenDiscourse automation workflows.
"""
import os
import time
import pytest
import requests
from minio import Minio

class TestAutomationWorkflow:
    """End-to-end tests for automation workflows."""
    
    @pytest.fixture(autouse=True)
    def setup(self, n8n_service, minio_service):
        self.n8n_url = n8n_service
        self.minio_client = Minio(
            minio_service.replace("http://", ""),
            access_key=os.getenv("MINIO_ACCESS_KEY", "minioadmin"),
            secret_key=os.getenv("MINIO_SECRET_KEY", "minioadmin"),
            secure=False
        )
        self.bucket_name = os.getenv("BACKUP_BUCKET", "opendiscourse-backups")
        self.auth = (
            os.getenv("N8N_USER", "admin"),
            os.getenv("N8N_PASSWORD", "admin")
        )
        self.headers = {"Content-Type": "application/json"}
        
        # Ensure bucket exists
        if not self.minio_client.bucket_exists(self.bucket_name):
            self.minio_client.make_bucket(self.bucket_name)
    
    def test_backup_workflow(self):
        """Test the complete backup workflow."""
        # 1. Create a test workflow in n8n
        workflow = {
            "name": "Test Backup Workflow",
            "nodes": [
                {
                    "name": "Start",
                    "type": "n8n-nodes-base.start",
                    "typeVersion": 1,
                    "position": [250, 300],
                    "parameters": {}
                },
                {
                    "name": "Execute Command",
                    "type": "n8n-nodes-base.executeCommand",
                    "typeVersion": 1,
                    "position": [450, 300],
                    "parameters": {
                        "command": "echo 'test backup content' > /tmp/test_backup.txt && tar -czf /tmp/test_backup.tar.gz /tmp/test_backup.txt"
                    }
                },
                {
                    "name": "S3 Upload",
                    "type": "n8n-nodes-base.s3",
                    "typeVersion": 1,
                    "position": [650, 300],
                    "parameters": {
                        "authentication": "predefinedCredentialType",
                        "s3UploadOperation": "upload",
                        "bucketName": self.bucket_name,
                        "fileName": "test_backup_workflow.tar.gz",
                        "filePath": "/tmp/test_backup.tar.gz"
                    },
                    "credentials": {
                        "s3": {
                            "id": "minio-credentials",
                            "name": "MinIO Credentials"
                        }
                    }
                }
            ],
            "connections": {
                "Start": {
                    "main": [[{"node": "Execute Command", "type": "main", "index": 0}]]
                },
                "Execute Command": {
                    "main": [[{"node": "S3 Upload", "type": "main", "index": 0}]]
                }
            }
        }
        
        # Create the workflow
        response = requests.post(
            f"{self.n8n_url}/rest/workflows",
            json=workflow,
            auth=self.auth,
            headers=self.headers,
            timeout=30
        )
        assert response.status_code == 200
        workflow_id = response.json()["id"]
        
        try:
            # Execute the workflow
            response = requests.post(
                f"{self.n8n_url}/rest/workflows/{workflow_id}/run",
                auth=self.auth,
                headers=self.headers,
                timeout=30
            )
            assert response.status_code == 200
            
            # Wait for the backup to complete
            time.sleep(5)
            
            # Verify the backup file exists in MinIO
            objects = list(self.minio_client.list_objects(self.bucket_name))
            assert any(obj.object_name == "test_backup_workflow.tar.gz" for obj in objects)
            
        finally:
            # Cleanup
            try:
                self.minio_client.remove_object(self.bucket_name, "test_backup_workflow.tar.gz")
            except Exception as e:
                print(f"Cleanup error: {e}")
            
            # Delete the test workflow
            requests.delete(
                f"{self.n8n_url}/rest/workflows/{workflow_id}",
                auth=self.auth,
                headers=self.headers,
                timeout=10
            )
