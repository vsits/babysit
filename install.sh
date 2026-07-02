#!/bin/bash
# Install the /babysit skill for Claude Code
set -e

SKILL_DIR="$HOME/.claude/skills/babysit"

mkdir -p "$SKILL_DIR"

# If running from a cloned repo, copy locally
if [ -f "SKILL.md" ]; then
  cp SKILL.md "$SKILL_DIR/SKILL.md"
  echo "Installed /babysit skill from local file."
else
  # Otherwise fetch from GitHub
  curl -fsSL \
    https://raw.githubusercontent.com/vsits/babysit/main/SKILL.md \
    -o "$SKILL_DIR/SKILL.md"
  echo "Installed /babysit skill from GitHub."
fi

# Ensure state directory exists
mkdir -p "$HOME/.claude/babysit"

echo "Restart Claude Code to pick up the new skill."
echo "Usage: /babysit  |  /babysit 2h  |  /babysit overnight"
