#!/usr/bin/env python3
"""
Extract a Claude conversation archive (data export zip) to markdown files.

Usage:
    python extract_claude_archive.py <archive.zip or batch-directory>

Accepts either a .zip file (which will be extracted to a sibling directory)
or an already-extracted batch directory containing conversations.json,
projects.json, memories.json, and users.json.
Output goes into <batch-directory>/conversations_md/.

Also extracts:
- projects/ — project knowledge files, custom instructions, and metadata
- created_files/ — files produced by the create_file tool
- artifacts/ — code and markdown artifacts
"""

import json
import os
import re
import sys
import zipfile
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote


# Map artifact language values to file extensions
LANGUAGE_EXTENSIONS = {
    'clojure': '.clj', 'clojurescript': '.cljs', 'python': '.py',
    'javascript': '.js', 'typescript': '.ts', 'html': '.html',
    'css': '.css', 'java': '.java', 'ruby': '.rb', 'go': '.go',
    'rust': '.rs', 'c': '.c', 'cpp': '.cpp', 'c++': '.cpp',
    'shell': '.sh', 'bash': '.sh', 'sql': '.sql', 'json': '.json',
    'yaml': '.yaml', 'xml': '.xml', 'markdown': '.md', 'swift': '.swift',
    'kotlin': '.kt', 'scala': '.scala', 'php': '.php', 'r': '.r',
    'lua': '.lua', 'perl': '.pl', 'elixir': '.ex', 'erlang': '.erl',
    'haskell': '.hs', 'dart': '.dart', 'zig': '.zig', 'nim': '.nim',
    'tsx': '.tsx', 'jsx': '.jsx', 'toml': '.toml', 'ini': '.ini',
    'csv': '.csv',
}


def sanitize_filename(name: str, max_length: int = 80) -> str:
    if not name or not name.strip():
        return "untitled"
    name = re.sub(r'[<>:"/\\|?*]', '-', name)
    name = re.sub(r'\s+', ' ', name).strip()
    name = name[:max_length]
    return name or "untitled"


def format_timestamp(ts: str) -> str:
    if not ts:
        return ""
    try:
        dt = datetime.fromisoformat(ts.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d %H:%M:%S UTC')
    except Exception:
        return ts


def safe_id(name: str) -> str:
    """Sanitize a string for use as a filename component (no slashes, etc.)."""
    return re.sub(r'[<>:"/\\|?*]', '_', name)


def artifact_extension(inp: dict) -> str:
    """Derive file extension from artifact type and language."""
    art_type = inp.get('type', '')
    lang = (inp.get('language') or '').lower()
    if lang and lang in LANGUAGE_EXTENSIONS:
        return LANGUAGE_EXTENSIONS[lang]
    if 'markdown' in art_type:
        return '.md'
    if 'code' in art_type:
        return '.txt'
    return '.txt'


def render_tool_use(item: dict) -> str:
    """Return a one-line markdown summary for a tool_use content block."""
    name = item.get('name', '')
    inp = item.get('input', {})

    if name == 'create_file':
        path = inp.get('path', '')
        fname = os.path.basename(path) if path else 'unknown'
        return f"Created: [{fname}](../../created_files/{fname})"

    if name == 'artifacts':
        cmd = inp.get('command', '')
        if cmd == 'create':
            title = inp.get('title', inp.get('id', 'untitled'))
            art_id = safe_id(inp.get('id', 'unknown'))
            ext = artifact_extension(inp)
            return f"Artifact: [{title}](../../artifacts/{art_id}{ext})"
        else:
            art_id = inp.get('id', 'unknown')
            return f"Updated artifact: {art_id}"

    if name == 'web_search':
        query = inp.get('query', '')
        return f"Searched: {query}"

    if name == 'web_fetch':
        url = inp.get('url', '')
        return f"Fetched: {url}"

    if name == 'bash_tool':
        cmd = inp.get('command', '')
        snippet = cmd[:120] + ('...' if len(cmd) > 120 else '')
        return f"Ran: `{snippet}`"

    if name == 'view':
        path = inp.get('path', '')
        return f"Viewed: `{path}`"

    if name == 'str_replace':
        path = inp.get('path', '')
        return f"Edited: `{path}`"

    return f"Used tool: {name}"


def render_message_content(message: dict) -> str:
    """Render all content blocks of a message into markdown.

    Handles text, thinking, tool_use (inline summaries), and skips tool_result.
    """
    content = message.get('content')
    if not content:
        text = message.get('text', '').strip()
        return text if text else ''

    parts = []
    for item in content:
        block_type = item.get('type', '')

        if block_type == 'text':
            text = (item.get('text') or '').strip()
            if text:
                parts.append(text)

        elif block_type == 'thinking':
            thinking = (item.get('thinking') or '').strip()
            if thinking:
                parts.append(
                    "<details>\n<summary>Thinking</summary>\n\n"
                    + thinking
                    + "\n\n</details>"
                )

        elif block_type == 'tool_use':
            summary = render_tool_use(item)
            if summary:
                parts.append(f"> {summary}")

        # skip tool_result, token_budget, flag, etc.

    return '\n\n'.join(parts)


def collect_created_files(conv: dict) -> list[dict]:
    """Extract create_file tool uses from a conversation."""
    results = []
    for msg in conv.get('chat_messages', []):
        for item in (msg.get('content') or []):
            if item.get('type') == 'tool_use' and item.get('name') == 'create_file':
                inp = item.get('input', {})
                path = inp.get('path', '')
                text = inp.get('file_text', '')
                if path and text:
                    results.append({
                        'path': path,
                        'filename': os.path.basename(path),
                        'content': text,
                    })
    return results


def collect_artifacts(conv: dict) -> list[dict]:
    """Extract artifact creates from a conversation."""
    results = []
    for msg in conv.get('chat_messages', []):
        for item in (msg.get('content') or []):
            if item.get('type') == 'tool_use' and item.get('name') == 'artifacts':
                inp = item.get('input', {})
                if inp.get('command') == 'create':
                    art_id = safe_id(inp.get('id', 'unknown'))
                    ext = artifact_extension(inp)
                    results.append({
                        'id': art_id,
                        'title': inp.get('title', art_id),
                        'ext': ext,
                        'language': inp.get('language', ''),
                        'type': inp.get('type', ''),
                        'content': inp.get('content', ''),
                    })
    return results


def format_conversation_markdown(conv: dict) -> str:
    lines = []

    name = conv.get('name', 'Untitled Conversation')
    lines.append(f"# {name}\n")

    lines.append("## Metadata\n")
    lines.append(f"- **UUID:** `{conv.get('uuid', 'N/A')}`")
    lines.append(f"- **Created:** {format_timestamp(conv.get('created_at', ''))}")
    lines.append(f"- **Updated:** {format_timestamp(conv.get('updated_at', ''))}")

    summary = conv.get('summary', '')
    if summary:
        lines.append(f"\n## Summary\n")
        lines.append(summary)

    messages = conv.get('chat_messages', [])
    if messages:
        lines.append(f"\n## Conversation ({len(messages)} messages)\n")

        for msg in messages:
            sender = msg.get('sender', 'unknown')
            timestamp = format_timestamp(msg.get('created_at', ''))

            sender_display = "**Human**" if sender == "human" else "**Claude**"

            lines.append(f"### {sender_display}")
            if timestamp:
                lines.append(f"*{timestamp}*\n")

            rendered = render_message_content(msg)
            if rendered:
                lines.append(rendered)
            else:
                lines.append("*(empty message)*")

            attachments = msg.get('attachments', [])
            if attachments:
                lines.append(f"\n*{len(attachments)} attachment(s)*")

            files = msg.get('files', [])
            if files:
                lines.append(f"\n*{len(files)} file(s)*")

            lines.append("\n---\n")

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <archive.zip or batch-directory>")
        sys.exit(1)

    target = Path(sys.argv[1]).resolve()

    # Handle zip file: extract to sibling directory with same name minus .zip
    if target.is_file() and target.suffix == '.zip':
        batch_dir = target.with_suffix('')
        if batch_dir.exists():
            print(f"Using existing directory: {batch_dir}")
        else:
            print(f"Extracting {target.name} to {batch_dir}...")
            batch_dir.mkdir(parents=True)
            with zipfile.ZipFile(target, 'r') as zf:
                zf.extractall(batch_dir)
            print(f"Extracted {len(zipfile.ZipFile(target).namelist())} files")
    elif target.is_dir():
        batch_dir = target
    else:
        print(f"Error: {target} is not a zip file or directory")
        sys.exit(1)

    conversations_file = batch_dir / 'conversations.json'
    if not conversations_file.exists():
        print(f"Error: {conversations_file} not found")
        sys.exit(1)

    # Derive export date from directory name (data-YYYY-MM-DD-...)
    dir_name = batch_dir.name
    export_date = "unknown"
    m = re.search(r'data-(\d{4}-\d{2}-\d{2})', dir_name)
    if m:
        export_date = m.group(1)

    # Load conversations
    print(f"Loading {conversations_file}...")
    with open(conversations_file, 'r', encoding='utf-8') as f:
        conversations = json.load(f)
    print(f"Found {len(conversations)} conversations")

    # Create output directories
    output_dir = batch_dir / 'conversations_md'
    output_dir.mkdir(exist_ok=True)

    created_files_dir = batch_dir / 'created_files'
    created_files_dir.mkdir(exist_ok=True)

    artifacts_dir = batch_dir / 'artifacts'
    artifacts_dir.mkdir(exist_ok=True)

    # Group by year-month
    conversations_by_month = {}
    for conv in conversations:
        created = conv.get('created_at', '')
        if created:
            try:
                dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
                month_key = dt.strftime('%Y-%m')
            except Exception:
                month_key = 'unknown'
        else:
            month_key = 'unknown'

        if month_key not in conversations_by_month:
            conversations_by_month[month_key] = []
        conversations_by_month[month_key].append(conv)

    # Process each conversation
    total = 0
    index_entries = []
    all_created_files = []   # (filename_on_disk, original_path, conv_name, conv_md_link)
    all_artifacts = []       # (filename_on_disk, title, conv_name, conv_md_link)
    seen_created_filenames = {}  # basename -> count for dedup

    for month_key in sorted(conversations_by_month.keys()):
        month_dir = output_dir / month_key
        month_dir.mkdir(exist_ok=True)

        for conv in conversations_by_month[month_key]:
            name = conv.get('name', '') or 'Untitled'
            uuid_short = conv.get('uuid', 'unknown')[:8]
            created = conv.get('created_at', '')

            if created:
                try:
                    dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
                    date_prefix = dt.strftime('%Y%m%d-%H%M')
                except Exception:
                    date_prefix = 'unknown'
            else:
                date_prefix = 'unknown'

            safe_name = sanitize_filename(name, 60)
            filename = f"{date_prefix}_{safe_name}_{uuid_short}.md"
            conv_md_link = f"conversations_md/{month_key}/{filename}"

            filepath = month_dir / filename
            markdown = format_conversation_markdown(conv)

            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(markdown)

            # Extract created files
            for cf in collect_created_files(conv):
                basename = cf['filename']
                if basename in seen_created_filenames:
                    seen_created_filenames[basename] += 1
                    # Deduplicate: prefix with date and uuid snippet
                    disk_name = f"{date_prefix}_{uuid_short}_{basename}"
                else:
                    seen_created_filenames[basename] = 1
                    disk_name = basename

                out_path = created_files_dir / disk_name
                with open(out_path, 'w', encoding='utf-8') as f:
                    f.write(cf['content'])
                all_created_files.append((disk_name, cf['path'], name, conv_md_link))

            # Extract artifacts
            for art in collect_artifacts(conv):
                disk_name = f"{art['id']}{art['ext']}"
                out_path = artifacts_dir / disk_name
                with open(out_path, 'w', encoding='utf-8') as f:
                    f.write(art['content'])
                all_artifacts.append((disk_name, art['title'], name, conv_md_link))

            msg_count = len(conv.get('chat_messages', []))
            index_entries.append({
                'month': month_key,
                'name': name,
                'created': created,
                'msg_count': msg_count,
                'filename': f"{month_key}/{filename}",
                'summary': conv.get('summary', '')[:200] if conv.get('summary') else ''
            })

            total += 1
            if total % 100 == 0:
                print(f"  Processed {total} conversations...")

    print(f"Extracted {total} conversations to {output_dir}")
    print(f"Extracted {len(all_created_files)} created files to {created_files_dir}")
    print(f"Extracted {len(all_artifacts)} artifacts to {artifacts_dir}")

    # Create created_files/INDEX.md
    if all_created_files:
        cf_index = ["# Created Files\n"]
        cf_index.append(f"**Total:** {len(all_created_files)} files\n")
        for disk_name, orig_path, conv_name, conv_link in all_created_files:
            cf_index.append(f"- [{disk_name}]({disk_name})")
            cf_index.append(f"  - Original path: `{orig_path}`")
            cf_index.append(f"  - From: [{conv_name}](../{conv_link})")
        with open(created_files_dir / 'INDEX.md', 'w', encoding='utf-8') as f:
            f.write('\n'.join(cf_index))
        print("Created created_files/INDEX.md")

    # Create artifacts/INDEX.md
    if all_artifacts:
        art_index = ["# Artifacts\n"]
        art_index.append(f"**Total:** {len(all_artifacts)} artifacts\n")
        for disk_name, title, conv_name, conv_link in all_artifacts:
            art_index.append(f"- [{title}]({disk_name})")
            art_index.append(f"  - From: [{conv_name}](../{conv_link})")
        with open(artifacts_dir / 'INDEX.md', 'w', encoding='utf-8') as f:
            f.write('\n'.join(art_index))
        print("Created artifacts/INDEX.md")

    # Create conversation index file
    print("Creating index file...")
    index_lines = ["# Claude Conversation Archive Index\n"]
    index_lines.append(f"**Total Conversations:** {total}\n")
    index_lines.append(f"**Export Date:** {export_date}\n")

    index_lines.append("## Statistics by Month\n")
    for month in sorted(conversations_by_month.keys()):
        count = len(conversations_by_month[month])
        index_lines.append(f"- **{month}:** {count} conversations")

    index_lines.append("\n## All Conversations\n")

    current_month = None
    for entry in sorted(index_entries, key=lambda x: x.get('created', ''), reverse=True):
        month = entry['month']
        if month != current_month:
            index_lines.append(f"\n### {month}\n")
            current_month = month

        name = entry['name'] or 'Untitled'
        link = entry['filename']
        msg_count = entry['msg_count']
        summary = entry.get('summary', '')

        index_lines.append(f"- [{name}]({link}) ({msg_count} messages)")
        if summary:
            index_lines.append(f"  - {summary[:150]}...")

    with open(output_dir / 'INDEX.md', 'w', encoding='utf-8') as f:
        f.write('\n'.join(index_lines))
    print("Created INDEX.md")

    # Export projects with knowledge files
    projects_file = batch_dir / 'projects.json'
    if projects_file.exists():
        print("\nExporting projects...")
        with open(projects_file, 'r', encoding='utf-8') as f:
            projects = json.load(f)

        projects_dir = batch_dir / 'projects'
        projects_dir.mkdir(exist_ok=True)

        total_docs = 0
        skipped_empty = 0
        projects_index = ["# Projects\n"]

        for proj in projects:
            proj_name = proj.get('name', 'Unnamed')
            proj_safe = sanitize_filename(proj_name, 80)
            proj_dir = projects_dir / proj_safe
            proj_dir.mkdir(exist_ok=True)

            docs = proj.get('docs', [])
            description = proj.get('description', '')
            prompt_template = proj.get('prompt_template', '')

            # Write _PROJECT.md with metadata and instructions
            meta = [f"# {proj_name}\n"]
            meta.append(f"- **UUID:** `{proj.get('uuid', 'N/A')}`")
            meta.append(f"- **Created:** {format_timestamp(proj.get('created_at', ''))}")
            meta.append(f"- **Updated:** {format_timestamp(proj.get('updated_at', ''))}")
            meta.append(f"- **Knowledge docs:** {len(docs)}")
            if description:
                meta.append(f"\n## Description\n\n{description}")
            if prompt_template:
                meta.append(f"\n## Custom Instructions\n\n```\n{prompt_template}\n```")
            if docs:
                meta.append(f"\n## Knowledge Files\n")
                for doc in docs:
                    decoded = unquote(doc.get('filename', 'untitled'))
                    content_len = len(doc.get('content', ''))
                    meta.append(f"- [{decoded}]({decoded}) ({content_len:,} chars)")

            with open(proj_dir / '_PROJECT.md', 'w', encoding='utf-8') as f:
                f.write('\n'.join(meta))

            # Write each knowledge doc to disk
            doc_count = 0
            for doc in docs:
                raw_filename = doc.get('filename', '')
                content = doc.get('content', '')
                if not content:
                    skipped_empty += 1
                    continue
                decoded = unquote(raw_filename) if raw_filename else 'untitled.txt'
                # Sanitize each path component but preserve directory structure
                parts = Path(decoded).parts
                safe_parts = [sanitize_filename(p, 120) for p in parts]
                doc_path = proj_dir / Path(*safe_parts)
                doc_path.parent.mkdir(parents=True, exist_ok=True)
                with open(doc_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                doc_count += 1

            total_docs += doc_count

            # Add to projects index
            doc_label = f"{len(docs)} docs" if docs else "no docs"
            projects_index.append(f"- **[{proj_name}](projects/{proj_safe}/_PROJECT.md)** — {doc_label}")
            if description:
                projects_index.append(f"  - {description[:150]}")

        # Write projects/INDEX.md
        projects_index.insert(1, f"**Total:** {len(projects)} projects, {total_docs} knowledge files extracted\n")
        with open(projects_dir / 'INDEX.md', 'w', encoding='utf-8') as f:
            f.write('\n'.join(projects_index))

        # Write PROJECTS.md in conversations_md for backward compat
        with open(output_dir / 'PROJECTS.md', 'w', encoding='utf-8') as f:
            f.write('\n'.join(projects_index))

        print(f"Extracted {total_docs} knowledge files across {len(projects)} projects to {projects_dir}")
        if skipped_empty:
            print(f"  Skipped {skipped_empty} empty doc(s)")
    else:
        projects = []

    # Export memories
    memories_file = batch_dir / 'memories.json'
    if memories_file.exists():
        print("Exporting memories...")
        with open(memories_file, 'r', encoding='utf-8') as f:
            memories = json.load(f)

        memories_md = ["# Claude Memories\n"]
        project_names = {p['uuid']: p['name'] for p in projects}

        for mem in memories:
            conv_mem = mem.get('conversations_memory', '')
            if conv_mem:
                memories_md.append("## General Conversation Memory\n")
                memories_md.append(conv_mem)
                memories_md.append("\n---\n")

            proj_mems = mem.get('project_memories', {})
            if proj_mems:
                memories_md.append("## Project Memories\n")
                for proj_uuid, proj_mem in proj_mems.items():
                    proj_name = project_names.get(proj_uuid, proj_uuid)
                    memories_md.append(f"### {proj_name}\n")
                    memories_md.append(proj_mem)
                    memories_md.append("\n---\n")

        with open(output_dir / 'MEMORIES.md', 'w', encoding='utf-8') as f:
            f.write('\n'.join(memories_md))
        print("Exported MEMORIES.md")

    print("\nDone!")


if __name__ == '__main__':
    main()
