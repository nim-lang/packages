import json
import os
import re
import subprocess
import sys

def get_repo_from_url(url):
    """Extracts owner/repo from a GitHub URL."""
    match = re.search(r"github\.com/([^/]+)/([^/]+)", url)
    if match:
        return match.group(1), match.group(2).replace(".git", "")
    return None, None

def build_graphql_query(repos):
    """Builds a GraphQL query for a batch of repositories."""
    query_parts = []
    for i, (owner, repo) in enumerate(repos):
        query_parts.append(f"""
        repo{i}: repository(owner: "{owner}", name: "{repo}") {{
            isArchived
            nameWithOwner
        }}
        """)
    return "query {" + "".join(query_parts) + "}"

def run_gh_query(query):
    """Runs a GraphQL query using the gh CLI."""
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running gh command: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)

def main():
    """Main function."""
    batch_size = int(os.environ.get("BATCH_SIZE", 50))

    with open("packages.json", "r") as f:
        packages = json.load(f)

    github_repos = []
    for pkg in packages:
        if pkg.get("method") == "git" and "github.com" in pkg.get("url", ""):
            owner, repo = get_repo_from_url(pkg["url"])
            if owner and repo:
                github_repos.append((owner, repo, pkg))

    archived_repos = set()
    for i in range(0, len(github_repos), batch_size):
        batch = github_repos[i:i+batch_size]
        repos_to_query = [(owner, repo) for owner, repo, pkg in batch]
        query = build_graphql_query(repos_to_query)
        result = run_gh_query(query)

        if "data" in result:
            for key, repo_data in result["data"].items():
                if repo_data and repo_data.get("isArchived"):
                    archived_repos.add(repo_data["nameWithOwner"])

    updated = False
    for owner, repo, pkg in github_repos:
        name_with_owner = f"{owner}/{repo}"
        if name_with_owner in archived_repos:
            if "deleted" not in pkg.get("tags", []):
                if "tags" not in pkg:
                    pkg["tags"] = []
                pkg["tags"].append("deleted")
                print(f"Tagging {pkg['name']} as deleted.")
                updated = True

    if updated:
        with open("packages.json", "w") as f:
            json.dump(packages, f, indent=2, ensure_ascii=False)
            f.write('\n') # Add trailing newline
        print("packages.json updated.")
    else:
        print("No new archived repositories found.")

if __name__ == "__main__":
    main()
