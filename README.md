# rzodkiewiczmichal.github.io

Personal blog built with Hugo + PaperMod, deployed via GitHub Pages.

## Creating content

1. Add a markdown file to `posts/`:

```
posts/my-article.md
```

2. Start with a `# Heading` — it becomes the page title:

```markdown
# Virtual Threads Deep Dive

Java 21 introduced virtual threads...
```

3. Push to `main`. GitHub Actions handles the rest.

The site builds automatically and publishes to https://rzodkiewiczmichal.github.io/

## What happens under the hood

`scripts/prepare-posts.sh` runs before Hugo build and:
- Extracts the `# Heading` as the post title
- Sets the date from the git commit
- Generates Hugo frontmatter
- Files that already have `---` frontmatter are used as-is

## Local preview

```bash
bash scripts/prepare-posts.sh
hugo server -D
# http://localhost:1313
```

## Setup (one-time)

In GitHub repo **Settings > Pages > Source**, select **GitHub Actions**.
