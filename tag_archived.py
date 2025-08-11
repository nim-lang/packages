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

    # Even with a non-zero exit code, gh might return a JSON with partial data
    # and an 'errors' field. We should try to parse it.
    if not result.stdout:
        print(f"Error running gh command: empty stdout. stderr: {result.stderr}", file=sys.stderr)
        # Return something that won't crash the main loop
        return {"data": {}}

    try:
        response_json = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"Error running gh command: failed to parse JSON. stderr: {result.stderr}", file=sys.stderr)
        return {"data": {}}

    if "errors" in response_json:
        # Filter out expected "NOT_FOUND" errors to avoid log spam.
        critical_errors = [e for e in response_json.get("errors", []) if e.get("type") != "NOT_FOUND"]
        if critical_errors:
            print(f"GraphQL query returned critical errors: {critical_errors}", file=sys.stderr)

    return response_json

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

    repos_to_delete = set()
    for i in range(0, len(github_repos), batch_size):
        batch = github_repos[i:i+batch_size]
        repos_to_query = [(owner, repo) for owner, repo, pkg in batch]
        query = build_graphql_query(repos_to_query)
        result = run_gh_query(query)

        if "data" in result and result["data"] is not None:
            for j, (owner, repo, pkg) in enumerate(batch):
                key = f"repo{j}"
                repo_data = result["data"].get(key)
                name_with_owner = f"{owner}/{repo}"

                if repo_data is None:  # Repo not found / deleted
                    repos_to_delete.add(name_with_owner)
                    print(f"Repository {name_with_owner} not found, marking as deleted.")
                elif repo_data.get("isArchived"):  # Repo is archived
                    repos_to_delete.add(name_with_owner)
                    print(f"Repository {name_with_owner} is archived, marking as deleted.")

    updated = False
    for owner, repo, pkg in github_repos:
        name_with_owner = f"{owner}/{repo}"
        if name_with_owner in repos_to_delete:
            pkg_tags = set(pkg.get("tags", []))
            if "deleted" not in pkg_tags:
                pkg_tags.add("deleted")
                pkg["tags"] = sorted(list(pkg_tags))
                print(f"Tagging {pkg['name']} as deleted.")
                updated = True

    if updated:
        with open("packages.json", "w") as f:
            json.dump(packages, f, indent=2, ensure_ascii=False)
            f.write('\n')  # Add trailing newline
        print("packages.json updated.")
    else:
        print("No new archived or deleted repositories found.")

if __name__ == "__main__":
    main()
