#!/bin/bash

# CI helper script to checkout the current packages.json and
# the version at the merge base to compare to.

set -e

# Repository and branch the PR will be merged into
targetRepository="https://github.com/$GITHUB_REPOSITORY"
targetBranch="$GITHUB_BASE_REF"

# Create a branch of the current repository state because actions/checkout
# leaves us with a detached HEAD
git branch merge-branch
# Backup the current packages.json because it will get overwritten by a
# checkout
cp packages.json packages.json.bak
# Fetch the merge target branch into a branch called "base"
git fetch "$targetRepository" "$targetBranch:base"
# Determine the last common commit (the merge base)
mergeBase="$(git merge-base merge-branch base)"
echo "Comparing against packages.json at $mergeBase"
# Checkout the package list at the branching point
git checkout "$mergeBase" packages.json
# PR version becomes packages.json and merge base becomes packages_old.json
mv packages.json packages_old.json
mv packages.json.bak packages.json
