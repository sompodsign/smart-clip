# SmartClip Marketing Agent

An AI agent team that autonomously generates marketing content for SmartClip.
All output goes to `output/` for human review before anything is published.

## Structure

```
marketing-agent/
├── run.py                  # Main orchestrator — run this
├── requirements.txt
├── context/
│   ├── product.md          # Product facts
│   ├── icp.md              # Ideal customer profile
│   └── brand-voice.md      # Tone, rules, approved comparisons
├── agents/
│   ├── orchestrator.md     # CMO agent — coordinates the team
│   ├── research.md         # Finds trends, competitor gaps, communities
│   ├── copywriter.md       # Tweets, Reddit posts, emails, landing page copy
│   ├── seo.md              # Keywords, blog briefs, comparison posts
│   └── outreach.md         # Community replies, Product Hunt, influencer outreach
├── output/                 # All generated content (gitignored)
│   ├── drafts/             # Individual content pieces
│   ├── weekly-execution-*.md # Day-by-day plan for the upcoming week
│   └── weekly-package-*.md # Full weekly review package
└── memory/                 # Persistent state across runs
    ├── performance-notes.md # What's working
    └── posted-log.md        # What's been published (fill in manually)
```

## Setup

```bash
cd marketing-agent
pip install -r requirements.txt
export ANTHROPIC_API_KEY=your_key_here
```

Or create a `.env` file in this directory:
```
ANTHROPIC_API_KEY=sk-ant-...
```

## Usage

```bash
# Full weekly run (generates research + content + SEO + outreach)
python run.py

# Individual tasks
python run.py --task research   # Market research only
python run.py --task content    # Social + email drafts only
python run.py --task seo        # Blog post + keywords only
python run.py --task outreach   # Reddit replies + PH + influencer emails
```

## Workflow

1. Run `python run.py` (takes ~2-3 minutes)
2. Open `output/weekly-execution-[date].md`
3. Follow the day-by-day plan instead of posting everything at once
4. Open `output/weekly-package-[date].md` when you want the full draft set and research context
5. Update `memory/posted-log.md` with what you actually published
6. Update `memory/performance-notes.md` with what performed well

## Channels the Agent Targets

| Channel | Content Type |
|---|---|
| Twitter/X | Threads, single tweets |
| Reddit | r/macapps, r/productivity, r/MacOS posts + replies |
| Blog/SEO | Comparison posts, tutorials, use cases |
| Email | Welcome sequence, upgrade nudges |
| Product Hunt | Launch copy, maker comments |
| Influencers | Cold outreach emails |

## Customization

- Edit `context/product.md` when pricing or features change
- Edit `context/icp.md` when you learn more about your customers
- Edit `context/brand-voice.md` to adjust tone, link rules, and posting cadence
- Edit individual agent files in `agents/` to change what each produces

## Memory

After publishing, manually log what was posted:

```markdown
# memory/posted-log.md
- 2026-03-07: Tweet thread about developer clipboard use case — 800 impressions
- 2026-03-06: r/macapps post — 32 upvotes, 2 signups tracked
```

The agent reads this on the next run to avoid repetition.
