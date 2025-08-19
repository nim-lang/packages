import json
import os
import re
import subprocess
import sys
from urllib.parse import urlparse

def get_repo_from_url(url):
    """Extracts owner/repo from a GitHub URL, stripping query parameters."""
    # Use urlparse to handle URL components correctly
    parsed_url = urlparse(url)
    if parsed_url.netloc == "github.com":
        path_parts = parsed_url.path.strip('/').split('/')
        if len(path_parts) >= 2:
            owner = path_parts[0]
            repo = path_parts[1]
            if repo.endswith('.git'):
                repo = repo[:-4]
            return owner, repo
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
        all_packages = json.load(f)

    # Partition packages: those already marked 'deleted' vs. those to be checked.
    packages_to_check = []
    deleted_packages = []
    for pkg in all_packages:
        if "deleted" in pkg.get("tags", []):
            deleted_packages.append(pkg)
        else:
            packages_to_check.append(pkg)

    # Identify GitHub repos to query from the packages to be checked.
    github_repos_map = {}
    for pkg in packages_to_check:
        owner, repo = get_repo_from_url(pkg.get("url", ""))
        if owner and repo:
            name_with_owner = f"{owner}/{repo}"
            # Handle cases where multiple packages point to the same repo.
            if name_with_owner not in github_repos_map:
                github_repos_map[name_with_owner] = []
            github_repos_map[name_with_owner].append(pkg)

    # Batch query the GitHub API.
    repos_to_query = list(github_repos_map.keys())
    api_results = {}
    for i in range(0, len(repos_to_query), batch_size):
        batch_repos_str = repos_to_query[i:i+batch_size]
        batch_repos_tuple = [tuple(r.split('/')) for r in batch_repos_str]
        query = build_graphql_query(batch_repos_tuple)
        result = run_gh_query(query)
        if "data" in result and result.get("data") is not None:
            for j, repo_str in enumerate(batch_repos_str):
                key = f"repo{j}"
                api_results[repo_str] = result["data"].get(key)

    # Process API results.
    newly_deleted_names = []
    newly_archived_names = []
    active_packages = []

    # Start with a clean list of packages to check
    remaining_packages = list(packages_to_check)

    for repo_str, repo_data in api_results.items():
        packages_to_update = github_repos_map[repo_str]
        for pkg in packages_to_update:
            if repo_data is None:  # Repo not found, move to deleted.
                if pkg in remaining_packages:
                    deleted_packages.append(pkg)
                    remaining_packages.remove(pkg)
                    newly_deleted_names.append(pkg['name'])
            elif repo_data.get("isArchived"):  # Repo is archived, tag it.
                pkg_tags = set(pkg.get("tags", []))
                if "archived" not in pkg_tags:
                    pkg_tags.add("archived")
                    pkg["tags"] = sorted(list(pkg_tags))
                    newly_archived_names.append(pkg['name'])

    active_packages = remaining_packages

    # Write output files if changes were made.
    if newly_deleted_names or newly_archived_names:
        # Write active packages to packages.json
        with open("packages.json", "w") as f:
            json.dump(active_packages, f, indent=2, ensure_ascii=False)
            f.write('\n')

        # Write deleted packages to deleted_packages.json
        if deleted_packages:
            with open("deleted_packages.json", "w") as f:
                json.dump(deleted_packages, f, indent=2, ensure_ascii=False)
                f.write('\n')

        # Print summary for commit message.
        if newly_deleted_names:
            print("Moved to deleted_packages.json:")
            for name in sorted(list(set(newly_deleted_names))):
                print(f"- {name}")
        if newly_archived_names:
            if newly_deleted_names:
                print() # Add a newline for separation.
            print("Tagged as archived:")
            for name in sorted(list(set(newly_archived_names))):
                print(f"- {name}")
    else:
        print("No new archived or deleted repositories found.")

if __name__ == "__main__":
    main()
