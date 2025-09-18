import os
import json
import logging
from datetime import datetime
from typing import List, Dict, Any
from pydantic import ValidationError
import github
from atlassian import Jira, Bitbucket
from linear import Client as LinearClient
from tenacity import retry, stop_after_attempt, wait_exponential
from pika import BasicProperties
import pika

from ..schemas.sync_entities import GitHubIssue, ExternalTask

# Setup JSON logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class GitHubSyncAgent:
    def __init__(self):
        self.github_token = os.getenv('GITHUB_TOKEN')
        self.jira_url = os.getenv('JIRA_URL')
        self.jira_username = os.getenv('JIRA_USERNAME')
        self.jira_password = os.getenv('JIRA_PASSWORD')
        self.bitbucket_username = os.getenv('BITBUCKET_USERNAME')
        self.bitbucket_password = os.getenv('BITBUCKET_PASSWORD')
        self.linear_token = os.getenv('LINEAR_TOKEN')
        
        if not self.github_token:
            raise ValueError("GITHUB_TOKEN environment variable is required")
        
        self.gh = github.Github(self.github_token)
        
        # Initialize external clients
        self.jira = Jira(
            url=self.jira_url,
            username=self.jira_username,
            password=self.jira_password
        ) if all([self.jira_url, self.jira_username, self.jira_password]) else None
        
        self.bitbucket = Bitbucket(
            url='https://bitbucket.org',
            username=self.bitbucket_username,
            password=self.bitbucket_password
        ) if all([self.bitbucket_username, self.bitbucket_password]) else None
        
        self.linear = LinearClient(api_key=self.linear_token) if self.linear_token else None
        
        # RabbitMQ connection (stub - extend existing messaging/rabbitmq.py if available)
        self.rabbitmq_params = pika.ConnectionParameters(host='localhost')
        self.connection = None
        self.channel = None
        self.connect_rabbitmq()
        
        # Supabase connection (stub - extend data/supabase/client.py if available)
        self.supabase_url = os.getenv('SUPABASE_URL')
        self.supabase_key = os.getenv('SUPABASE_KEY')
        if not all([self.supabase_url, self.supabase_key]):
            logger.warning("Supabase credentials not set, persistence disabled")
            self.supabase_client = None
        else:
            # Assuming supabase-py is installed; import and initialize here
            from supabase import create_client, Client
            self.supabase_client: Client = create_client(self.supabase_url, self.supabase_key)
    
    def connect_rabbitmq(self):
        try:
            self.connection = pika.BlockingConnection(self.rabbitmq_params)
            self.channel = self.connection.channel()
            self.channel.queue_declare(queue='github_sync_queue', durable=True)
            logger.info("RabbitMQ connection established")
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            self.connection = None
            self.channel = None
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    def ingest_github_data(self, repo_name: str) -> List[Dict[str, Any]]:
        """Ingestion Module: Fetch repos, issues, projects via PyGitHub"""
        try:
            repo = self.gh.get_repo(repo_name)
            issues = repo.get_issues(state='all')
            data = []
            for issue in issues:
                data.append({
                    'id': issue.id,
                    'repo': repo_name,
                    'title': issue.title,
                    'status': issue.state,
                    'number': issue.number,
                    'updated_at': issue.updated_at.isoformat()
                })
            logger.info(f"Ingested {len(data)} issues from {repo_name}")
            return data
        except github.GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise
    
    def map_entities(self, github_data: List[Dict[str, Any]]) -> List[GitHubIssue]:
        """Mapping Processor: Transform GitHub entities using Pydantic models"""
        issues = []
        for item in github_data:
            try:
                issue = GitHubIssue(**item)
                issues.append(issue)
            except ValidationError as e:
                logger.error(f"Validation error mapping issue {item.get('id')}: {e}")
        logger.info(f"Mapped {len(issues)} GitHub issues")
        return issues
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    def sync_to_external(self, issue: GitHubIssue, external_type: str) -> ExternalTask:
        """Sync Adapter: Interface with external APIs for synchronization"""
        external_id = None
        try:
            if external_type == 'jira' and self.jira:
                # Create Jira issue
                jira_issue = self.jira.issue_create(
                    fields={
                        'project': {'key': 'PROJ'},  # Assume project key
                        'summary': issue.title,
                        'description': f"GitHub Issue #{issue.id}: {issue.title}",
                        'issuetype': {'name': 'Task'}
                    }
                )
                external_id = jira_issue['key']
            elif external_type == 'bitbucket' and self.bitbucket:
                # Create Bitbucket issue
                bb_issue = self.bitbucket.add_issue(
                    project_key='PROJ',
                    title=issue.title,
                    description=f"GitHub Issue #{issue.id}: {issue.title}",
                    kind='bug'  # or task
                )
                external_id = bb_issue['id']
            elif external_type == 'linear' and self.linear:
                # Create Linear issue
                linear_issue = self.linear.issues.create(
                    title=issue.title,
                    description=f"GitHub Issue #{issue.id}: {issue.title}",
                    team_id='your-team-id'  # Assume team ID
                )
                external_id = linear_issue['identifier']
            
            if external_id:
                task = ExternalTask(
                    type=external_type,
                    external_id=external_id,
                    synced_at=datetime.now()
                )
                issue.syncs_to.append(task)
                logger.info(f"Synced issue {issue.id} to {external_type}:{external_id}")
                return task
            else:
                logger.warning(f"No sync performed for {external_type} - client not configured")
                return None
        except Exception as e:
            logger.error(f"Error syncing to {external_type}: {e}")
            raise
    
    def resolve_conflicts(self, issue: GitHubIssue, existing_task: ExternalTask) -> bool:
        """Conflict Resolver: Basic versioning check"""
        # Simple check: if GitHub updated_at > synced_at, update external
        if issue.id and hasattr(issue, 'updated_at') and existing_task.synced_at:
            gh_updated = datetime.fromisoformat(issue.updated_at.replace('Z', '+00:00'))
            if gh_updated > existing_task.synced_at:
                logger.info(f"Conflict detected for issue {issue.id}, updating external task")
                # Here, update the external task (call sync_to_external with update flag)
                return True
        return False
    
    def enqueue_for_sync(self, issue_data: Dict[str, Any]):
        """Enqueue to RabbitMQ queue"""
        if self.channel:
            self.channel.basic_publish(
                exchange='',
                routing_key='github_sync_queue',
                body=json.dumps(issue_data),
                properties=BasicProperties(delivery_mode=2)  # Persistent
            )
            logger.info(f"Enqueued issue {issue_data.get('id')} for sync")
        else:
            logger.error("RabbitMQ not connected, cannot enqueue")
    
    def persist_to_supabase(self, issue: GitHubIssue):
        """Persist to Supabase"""
        if self.supabase_client:
            try:
                # Upsert GitHubIssue (assuming tables: github_issues, external_tasks)
                data = issue.dict()
                self.supabase_client.table('github_issues').upsert(data).execute()
                
                # Persist external tasks
                for task in issue.syncs_to:
                    task_data = task.dict()
                    task_data['github_issue_id'] = issue.id  # Foreign key
                    self.supabase_client.table('external_tasks').upsert(task_data).execute()
                
                logger.info(f"Persisted issue {issue.id} and {len(issue.syncs_to)} tasks to Supabase")
            except Exception as e:
                logger.error(f"Supabase persistence error: {e}")
        else:
            logger.warning("Supabase not configured, skipping persistence")
    
    def process_sync(self, repo_name: str, external_types: List[str] = ['jira', 'bitbucket', 'linear']):
        """Main sync process: ingest -> map -> enqueue/sync -> persist"""
        try:
            # Step 1: Ingest
            github_data = self.ingest_github_data(repo_name)
            
            # Step 2: Map
            issues = self.map_entities(github_data)
            
            # Step 3: Sync and enqueue
            for issue in issues:
                # Enqueue for async processing
                self.enqueue_for_sync(issue.dict())
                
                # For demo, sync directly (in production, consume from queue)
                for ext_type in external_types:
                    if self.sync_to_external(issue, ext_type):
                        # Check for conflicts (stub: assume no existing for now)
                        pass  # resolve_conflicts(issue, existing_task)
            
            # Step 4: Persist
            for issue in issues:
                self.persist_to_supabase(issue)
                
        except Exception as e:
            logger.error(f"Sync process failed: {e}")
            # Could enqueue to retry/dead-letter queue
    
    def run_scheduled_sync(self, repo_name: str, interval_hours: int = 1):
        """Simple main function for scheduled sync (demo loop)"""
        import time
        logger.info(f"Starting scheduled sync for {repo_name} every {interval_hours} hours")
        while True:
            try:
                self.process_sync(repo_name)
                time.sleep(interval_hours * 3600)
            except KeyboardInterrupt:
                logger.info("Scheduled sync interrupted")
                break
            except Exception as e:
                logger.error(f"Scheduled sync error: {e}")
                time.sleep(60)  # Wait 1 min on error

if __name__ == "__main__":
    agent = GitHubSyncAgent()
    repo = os.getenv('GITHUB_REPO', 'owner/repo')  # Set env var
    agent.run_scheduled_sync(repo)