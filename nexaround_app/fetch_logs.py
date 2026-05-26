import urllib.request
import json
import zipfile
import io
import os

repo = "sinthujan23/nexaround"
api_url = f"https://api.github.com/repos/{repo}/actions/runs?per_page=1"

req = urllib.request.Request(api_url)
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        if not data['workflow_runs']:
            print("No workflow runs found.")
            exit(0)
        
        run = data['workflow_runs'][0]
        jobs_url = run['jobs_url']
        
        with urllib.request.urlopen(jobs_url) as jobs_response:
            jobs_data = json.loads(jobs_response.read().decode())
            job = jobs_data['jobs'][0]
            print(f"Run ID: {run['id']}, Job ID: {job['id']}, Status: {job['status']}, Conclusion: {job['conclusion']}")
            
            # The logs URL from the API for the job
            # Since downloading logs requires authentication for private repos, we check if it works.
            # But wait, public repo workflow logs can be downloaded.
            logs_url = f"https://api.github.com/repos/{repo}/actions/jobs/{job['id']}/logs"
            
            try:
                log_req = urllib.request.Request(logs_url)
                with urllib.request.urlopen(log_req) as log_response:
                    log_text = log_response.read().decode('utf-8')
                    lines = log_text.splitlines()
                    print("\n--- LAST 100 LINES OF LOG ---")
                    for line in lines[-100:]:
                        print(line)
            except Exception as e:
                print(f"Could not download logs directly (might need auth): {e}")

except Exception as e:
    print(f"Error fetching data: {e}")
