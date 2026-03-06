#!/usr/bin/env python3
"""
SmartClip Marketing Agent Orchestrator
Runs the full weekly marketing campaign generation pipeline.

Usage:
    python run.py                    # Full weekly run
    python run.py --task research    # Research only
    python run.py --task content     # Content drafts only
    python run.py --task seo         # SEO content only
    python run.py --task outreach    # Community outreach drafts only
"""

import os
import sys
import argparse
from datetime import date
from pathlib import Path
import anthropic
from dotenv import load_dotenv

load_dotenv(Path(__file__).parent / ".env")

# ── Config ──────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent
CONTEXT_DIR = BASE_DIR / "context"
AGENTS_DIR = BASE_DIR / "agents"
OUTPUT_DIR = BASE_DIR / "output"
DRAFTS_DIR = OUTPUT_DIR / "drafts"
MEMORY_DIR = BASE_DIR / "memory"

TODAY = date.today().isoformat()
MODEL = os.environ.get("MODEL", "claude-sonnet-4-6")

# ── Setup ────────────────────────────────────────────────────────────────────
def setup_dirs():
    for d in [OUTPUT_DIR, DRAFTS_DIR, MEMORY_DIR]:
        d.mkdir(parents=True, exist_ok=True)


def load_context() -> str:
    """Load all context files into a single system prompt."""
    files = ["product.md", "icp.md", "brand-voice.md"]
    parts = []
    for f in files:
        path = CONTEXT_DIR / f
        if path.exists():
            parts.append(f"## {f}\n{path.read_text()}")
    return "\n\n".join(parts)


def load_agent(name: str) -> str:
    path = AGENTS_DIR / f"{name}.md"
    return path.read_text() if path.exists() else ""


def load_memory() -> str:
    notes_path = MEMORY_DIR / "performance-notes.md"
    log_path = MEMORY_DIR / "posted-log.md"
    parts = []
    if notes_path.exists():
        parts.append(f"## Past Performance Notes\n{notes_path.read_text()}")
    if log_path.exists():
        parts.append(f"## Already Posted (avoid repeating)\n{log_path.read_text()}")
    return "\n\n".join(parts) if parts else ""


def save_output(filename: str, content: str):
    path = OUTPUT_DIR / filename
    path.write_text(content)
    print(f"  Saved: {path}")
    return path


def save_draft(filename: str, content: str):
    path = DRAFTS_DIR / filename
    path.write_text(content)
    print(f"  Saved draft: {path}")
    return path


# ── Agent Runner ─────────────────────────────────────────────────────────────
def run_agent(client: anthropic.Anthropic, agent_name: str, task: str) -> str:
    """Run a single specialist agent with a task."""
    context = load_context()
    agent_instructions = load_agent(agent_name)
    memory = load_memory()

    system = f"""You are a specialist marketing agent for SmartClip, a macOS clipboard manager app.

{agent_instructions}

---
PRODUCT CONTEXT:
{context}

{f"MEMORY / HISTORY:{chr(10)}{memory}" if memory else ""}

Today's date: {TODAY}
Output all content in clean markdown. Be specific and actionable.
"""

    print(f"  Running {agent_name} agent...")
    response = client.messages.create(
        model=MODEL,
        max_tokens=4096,
        system=system,
        messages=[{"role": "user", "content": task}],
    )
    return response.content[0].text


# ── Tasks ────────────────────────────────────────────────────────────────────
def task_research(client):
    print("\n[1/4] Research Agent...")
    result = run_agent(
        client,
        "research",
        (
            "Run a full weekly research report. "
            "Find: top community discussions about clipboard managers and clipboard history on Mac this week, "
            "competitor complaints (Paste app, Raycast clipboard, Alfred clipboard, cloud clipboard tools), "
            "trending macOS productivity topics, "
            "and recommend 5 specific content angles for this week."
        ),
    )
    save_output(f"weekly-research-{TODAY}.md", result)
    return result


def task_content(client, research_context: str = ""):
    print("\n[2/4] Copywriter Agent...")
    task = (
        f"Based on this week's research:\n\n{research_context}\n\n"
        if research_context
        else ""
    )
    task += (
        "Produce the following content drafts for SmartClip:\n"
        "1. One 5-tweet Twitter thread (hook + value + CTA)\n"
        "2. Three standalone tweets (different angles: developer, writer, privacy-focused user)\n"
        "3. One Reddit post for r/macapps (helpful, not promotional)\n"
        "4. One welcome email (post-download)\n"
        "5. One upgrade nudge email (day 3, hit free 5-item limit)\n\n"
        "Format each piece clearly with its channel label."
    )
    result = run_agent(client, "copywriter", task)
    save_draft(f"content-{TODAY}.md", result)
    return result


def task_seo(client):
    print("\n[3/4] SEO Agent...")
    result = run_agent(
        client,
        "seo",
        (
            "Do two things:\n"
            "1. List 15 long-tail keywords to target this month with estimated search intent\n"
            "2. Write a complete blog post: 'Does Mac Have Clipboard History? (And the Best Free Fix in 2026)' "
            "— 1000 words, naturally mention SmartClip as the solution, "
            "include meta description and suggested internal links."
        ),
    )
    save_draft(f"seo-blog-{TODAY}.md", result)
    return result


def task_outreach(client, research_context: str = ""):
    print("\n[4/4] Outreach Agent...")
    task = (
        f"Based on this week's research:\n\n{research_context}\n\n"
        if research_context
        else ""
    )
    task += (
        "Produce:\n"
        "1. 5 draft Reddit replies for threads where SmartClip is relevant "
        "(include the thread title/scenario you're replying to)\n"
        "2. A Product Hunt launch tagline, description, and first-comment draft\n"
        "3. 3 influencer outreach emails for macOS productivity YouTubers/newsletter writers\n\n"
        "Remember: helpful first, product second."
    )
    result = run_agent(client, "outreach", task)
    save_draft(f"outreach-{TODAY}.md", result)
    return result


def compile_weekly_package(research, content, seo, outreach):
    package = f"""# Weekly Marketing Package — {TODAY}

> Review all drafts below. Approve or edit before publishing to any channel.
> Nothing in this package has been posted anywhere yet.

---

## 1. Research Findings
{research}

---

## 2. Social & Email Content Drafts
{content}

---

## 3. SEO Blog Post Draft
{seo}

---

## 4. Community Outreach Drafts
{outreach}

---

## Action Checklist
- [ ] Review tweets — approve 1-2 to schedule this week
- [ ] Review Reddit post — post to r/macapps if feels natural
- [ ] Review blog post — publish to website after edits
- [ ] Review Reddit replies — post to matching threads
- [ ] Review outreach emails — send to influencer targets
- [ ] Update memory/posted-log.md after publishing
"""
    save_output(f"weekly-package-{TODAY}.md", package)
    print(f"\nWeekly package ready: output/weekly-package-{TODAY}.md")


# ── CLI ───────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="SmartClip Marketing Agent")
    parser.add_argument(
        "--task",
        choices=["research", "content", "seo", "outreach", "all"],
        default="all",
        help="Which task to run (default: all)",
    )
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("Error: ANTHROPIC_API_KEY environment variable not set.")
        print("Set it with: export ANTHROPIC_API_KEY=sk-ant-...")
        sys.exit(1)

    setup_dirs()
    client = anthropic.Anthropic(api_key=api_key)

    print(f"SmartClip Marketing Agent — {TODAY}")
    print("=" * 50)

    if args.task == "research":
        task_research(client)
    elif args.task == "content":
        task_content(client)
    elif args.task == "seo":
        task_seo(client)
    elif args.task == "outreach":
        task_outreach(client)
    else:
        # Full weekly run
        research = task_research(client)
        content = task_content(client, research)
        seo = task_seo(client)
        outreach = task_outreach(client, research)
        compile_weekly_package(research, content, seo, outreach)

    print("\nDone. Review drafts in output/ before publishing anything.")


if __name__ == "__main__":
    main()
