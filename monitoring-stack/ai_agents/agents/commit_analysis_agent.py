import os
import json
import logging
from datetime import datetime
from typing import List, Dict, Any, Optional
from pydantic import ValidationError

import github
from openai import OpenAI
import yaml
from tenacity import retry, stop_after_attempt, wait_exponential
import pika
import redis

from ..schemas.analysis_entities import Commit, Diff, Workflow, PullRequest
from ..schemas.sync_entities import GitHubIssue

# Setup JSON logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class CommitAnalysisAgent:
    def __init__(self):
        self.github_token = os.getenv('GITHUB_TOKEN')
        self.openai_api_key = os.getenv('OPENAI_API_KEY')
        
        if not self.github_token:
            raise ValueError("GITHUB_TOKEN environment variable is required")
        if not self.openai_api_key:
            raise ValueError("OPENAI_API_KEY environment variable is required")
        
        self.gh = github.Github(self.github_token)
        self.openai_client = OpenAI(api_key=self.openai_api_key)
        
        # RabbitMQ connection
        self.rabbitmq_params = pika.ConnectionParameters(host='localhost')
        self.connection = None
        self.channel = None
        self.connect_rabbitmq()
        
        # Supabase connection
        self.supabase_url = os.getenv('SUPABASE_URL')
        self.supabase_key = os.getenv('SUPABASE_KEY')
        if not all([self.supabase_url, self.supabase_key]):
            logger.warning("Supabase credentials not set, persistence disabled")
            self.supabase_client = None
        else:
            from supabase import create_client, Client
            self.supabase_client: Client = create_client(self.supabase_url, self.supabase_key)
        
        # Redis for caching
        self.redis_host = os.getenv('REDIS_HOST', 'localhost')
        self.redis_port = int(os.getenv('REDIS_PORT', 6379))
        self.redis_client = redis.Redis(host=self.redis_host, port=self.redis_port, decode_responses=True)
        
    def connect_rabbitmq(self):
        try:
            self.connection = pika.BlockingConnection(self.rabbitmq_params)
            self.channel = self.connection.channel()
            self.channel.queue_declare(queue='diff_analysis_queue', durable=True)
            logger.info("RabbitMQ connection established")
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            self.connection = None
            self.channel = None
    
    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=4, max=10))
    def fetch_diff(self, repo_name: str, commit_sha: str) -> Optional[Dict[str, Any]]:
        """Diff Fetcher: Retrieve commit diffs via PyGitHub"""
        try:
            repo = self.gh.get_repo(repo_name)
            commit = repo.get_commit(commit_sha)
            diff_files = commit.files
            changes = '\n'.join([f.file.name + ':\n' + f.patch for f in diff_files if f.patch])
            
            data = {
                'id': commit.sha,
                'repo': repo_name,
                'message': commit.commit.message,
                'diff_changes': changes,
                'file_changes': [f.file.name for f in diff_files],
                'created_at': commit.commit.author.date.isoformat()
            }
            logger.info(f"Fetched diff for commit {commit_sha} from {repo_name}")
            return data
        except github.GithubException as e:
            logger.error(f"GitHub API error: {e}")
            raise
    
    def analyze_diff_with_ai(self, diff_data: Dict[str, Any]) -> Dict[str, Any]:
        """AI Analyzer: Use OpenAI to parse diffs and infer tasks/workflows"""
        try:
            prompt = f"""Analyze this commit diff and generate suggested GitHub workflows, issues, and tasks.

Commit: {diff_data['message']}
Files changed: {', '.join(diff_data['file_changes'])}
Diff: {diff_data['diff_changes'][:2000]}  # Truncate for token limit

Output JSON with: workflows (list of YAML strings), issues (list of issue dicts), pr_suggestion (dict with title and body)."""
            
            response = self.openai_client.chat.completions.create(
                model="gpt-4",
                messages=[{"role": "user", "content": prompt}],
                temperature=0.3
            )
            analysis = json.loads(response.choices[0].message.content)
            analysis['commit_id'] = diff_data['id']
            analysis['repo'] = diff_data['repo']
            logger.info(f"AI analysis completed for commit {diff_data['id']}")
            return analysis
        except Exception as e:
            logger.error(f"AI analysis error: {e}")
            raise
    
    def generate_workflows(self, analysis: Dict[str, Any]) -> List[Workflow]:
        """Workflow Generator: Create GitHub workflows, issues, PRs based on analysis"""
        workflows = []
        for wf_data in analysis.get('workflows', []):
            try:
                workflow = Workflow(
                    commit_id=analysis['commit_id'],
                    yaml_content=wf_data,
                    generated_issues=[GitHubIssue(**issue) for issue in analysis.get('issues', []) if 'title' in issue],
                    created_at=datetime.now()
                )
                if workflow.validate_yaml():
                    workflows.append(workflow)
                else:
                    logger.warning(f"Invalid YAML for workflow from commit {analysis['commit_id']}")
            except ValidationError as e:
                logger.error(f"Validation error for workflow: {e}")
        logger.info(f"Generated {len(workflows)} valid workflows")
        return workflows
    
    def create_github_artifacts(self, repo_name: str, workflows: List[Workflow], pr_suggestion: Optional[Dict] = None):
        """Post generated artifacts to GitHub API"""
        try:
            repo = self.gh.get_repo(repo_name)
            created = []
            for workflow in workflows:
                # Create workflow file (simplified: assume .github/workflows/ path)
                repo.create_file(
                    path=f".github/workflows/analysis-{workflow.id}.yml",
                    message=f"Generated workflow from commit analysis",
                    content=workflow.yaml_content
                )
                created.append(workflow)
                
                # Create issues
                for issue in workflow.generated_issues:
                    repo.create_issue(title=issue.title, body=issue.title)  # Simplified
                    
            if pr_suggestion:
                # Create PR (requires base/head, simplified)
                pr = repo.create_pull(
                    title=pr_suggestion['title'],
                    body=pr_suggestion['body'],
                    head='branch',  # Assume
                    base='main'
                )
                created.append(PullRequest(title=pr_suggestion['title'], body=pr_suggestion['body'], diff_id=workflows[0].commit_id if workflows else '', repo=repo_name))
            
            logger.info(f"Created {len(created)} artifacts in {repo_name}")
            return created
        except Exception as e:
            logger.error(f"Error creating GitHub artifacts: {e}")
            raise
    
    def validate_artifacts(self, artifacts: List[Any]) -> bool:
        """Validation Engine: Basic schema checks with Pydantic"""
        for artifact in artifacts:
            try:
                if isinstance(artifact, Workflow):
                    if not artifact.validate_yaml():
                        return False
                # Add more validations as needed
            except Exception:
                return False
        return True
    
    def enqueue_for_analysis(self, diff_data: Dict[str, Any]):
        """Enqueue to RabbitMQ diff queue"""
        if self.channel:
            self.channel.basic_publish(
                exchange='',
                routing_key='diff_analysis_queue',
                body=json.dumps(diff_data),
                properties=pika.BasicProperties(delivery_mode=2)
            )
            logger.info(f"Enqueued diff {diff_data['id']} for analysis")
        else:
            logger.error("RabbitMQ not connected, cannot enqueue")
    
    def cache_analysis(self, commit_id: str, analysis: Dict[str, Any]):
        """Cache analysis metadata in Redis"""
        try:
            self.redis_client.setex(f"analysis:{commit_id}", 3600, json.dumps(analysis))  # 1 hour TTL
            logger.info(f"Cached analysis for {commit_id}")
        except Exception as e:
            logger.error(f"Redis cache error: {e}")
    
    def persist_to_supabase(self, commit: Commit, workflows: List[Workflow]):
        """Persist to Supabase"""
        if self.supabase_client:
            try:
                # Upsert Commit and Diff
                commit_data = commit.dict()
                self.supabase_client.table('commits').upsert(commit_data).execute()
                
                # Persist workflows
                for wf in workflows:
                    wf_data = wf.dict()
                    wf_data['commit_id'] = commit.id
                    self.supabase_client.table('workflows').upsert(wf_data).execute()
                
                logger.info(f"Persisted commit {commit.id} and {len(workflows)} workflows to Supabase")
            except Exception as e:
                logger.error(f"Supabase persistence error: {e}")
        else:
            logger.warning("Supabase not configured, skipping persistence")
    
    def process_analysis(self, repo_name: str, commit_sha: str):
        """Main analysis process: fetch -> analyze -> generate -> validate -> persist -> create"""
        try:
            # Step 1: Fetch diff
            diff_data = self.fetch_diff(repo_name, commit_sha)
            if not diff_data:
                return
            
            # Step 2: Enqueue (for async, but demo direct)
            self.enqueue_for_analysis(diff_data)
            
            # Step 3: AI Analyze (direct for demo)
            analysis = self.analyze_diff_with_ai(diff_data)
            self.cache_analysis(diff_data['id'], analysis)
            
            # Step 4: Generate workflows/issues/PRs
            workflows = self.generate_workflows(analysis)
            pr_suggestion = analysis.get('pr_suggestion')
            
            # Step 5: Validate
            if not self.validate_artifacts(workflows):
                logger.error("Artifact validation failed")
                return
            
            # Step 6: Create in GitHub
            created_artifacts = self.create_github_artifacts(repo_name, workflows, pr_suggestion)
            
            # Step 7: Persist
            commit = Commit(**diff_data, diff=Diff(**{k: v for k, v in diff_data.items() if k != 'diff'}), analyzed_by=workflows)
            self.persist_to_supabase(commit, workflows)
            
        except Exception as e:
            logger.error(f"Analysis process failed: {e}")
    
    def run_demo_analysis(self, repo_name: str, commit_sha: str):
        """Simple main function to run on webhook simulation (demo)"""
        logger.info(f"Starting demo analysis for commit {commit_sha} in {repo_name}")
        self.process_analysis(repo_name, commit_sha)
        

if __name__ == "__main__":
    agent = CommitAnalysisAgent()
    repo = os.getenv('GITHUB_REPO', 'owner/repo')
    commit = os.getenv('COMMIT_SHA', 'abc123')  # Set env var for demo
    agent.run_demo_analysis(repo, commit)