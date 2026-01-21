#!/usr/bin/env python3
"""
Estimate disk space required to download YouTube videos in 480p quality.
Reads video IDs or playlist URLs from a file or stdin and uses yt-dlp to get size estimates.
"""

import json
import subprocess
import sys
import argparse
import re
from concurrent.futures import ThreadPoolExecutor, as_completed


def is_playlist_url(text):
    """Check if the text is a YouTube playlist URL."""
    return "playlist?list=" in text or "/playlist/" in text


def get_playlist_videos(playlist_url, quality="480"):
    """
    Get video info for all videos in a playlist.

    Args:
        playlist_url: YouTube playlist URL
        quality: Desired height resolution (default: 480)

    Yields:
        Tuple of (size_in_bytes, title, error_message) for each video
    """
    try:
        # Use yt-dlp to get playlist info
        result = subprocess.run(
            [
                "yt-dlp",
                "--flat-playlist",
                "-J",
                playlist_url
            ],
            capture_output=True,
            text=True,
            timeout=60
        )

        if result.returncode != 0:
            yield None, None, f"Error fetching playlist: {result.stderr.strip()}"
            return

        playlist_info = json.loads(result.stdout)
        entries = playlist_info.get('entries', [])

        for entry in entries:
            video_id = entry.get('id')
            if video_id:
                yield video_id

    except subprocess.TimeoutExpired:
        yield None, None, "Timeout while fetching playlist"
    except json.JSONDecodeError:
        yield None, None, "Invalid JSON response from yt-dlp"
    except Exception as e:
        yield None, None, f"Unexpected error: {str(e)}"


def get_video_size(video_id_or_url, quality="480"):
    """
    Get estimated file size for a YouTube video at specified quality.

    Args:
        video_id_or_url: YouTube video ID or full URL
        quality: Desired height resolution (default: 480)

    Returns:
        Tuple of (size_in_bytes, title, error_message)
    """
    if video_id_or_url.startswith("http"):
        url = video_id_or_url
    else:
        url = f"https://www.youtube.com/watch?v={video_id_or_url}"

    try:
        # Use yt-dlp to get format information without downloading
        # Format selection: best video with height <= 480 + best audio
        result = subprocess.run(
            [
                "yt-dlp",
                "--dump-json",
                "-f", f"bv*[height<={quality}]+ba/b[height<={quality}]",
                url
            ],
            capture_output=True,
            text=True,
            timeout=30
        )

        if result.returncode != 0:
            return None, None, f"Error fetching video info: {result.stderr.strip()}"

        info = json.loads(result.stdout)

        # Get filesize - try different keys as yt-dlp may provide different info
        filesize = info.get('filesize') or info.get('filesize_approx') or 0

        # If filesize is not available, estimate from bitrate and duration
        if filesize == 0:
            duration = info.get('duration', 0)
            tbr = info.get('tbr', 0)  # total bitrate in kbps
            if duration and tbr:
                filesize = int((tbr * 1000 / 8) * duration)  # Convert kbps to bytes

        title = info.get('title', 'Unknown')

        return filesize, title, None

    except subprocess.TimeoutExpired:
        return None, None, "Timeout while fetching video info"
    except json.JSONDecodeError:
        return None, None, "Invalid JSON response from yt-dlp"
    except Exception as e:
        return None, None, f"Unexpected error: {str(e)}"


def format_size(bytes_size):
    """Convert bytes to human-readable format."""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_size < 1024.0:
            return f"{bytes_size:.2f} {unit}"
        bytes_size /= 1024.0
    return f"{bytes_size:.2f} PB"


def process_input(input_source):
    """
    Process input which can be JSON video IDs or playlist URLs (one per line).

    Args:
        input_source: File-like object to read from

    Returns:
        List of video IDs to process
    """
    content = input_source.read().strip()

    # Try JSON first
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        pass

    # Try as line-separated URLs/IDs
    lines = [line.strip() for line in content.split('\n') if line.strip()]

    video_ids = []
    for line in lines:
        if is_playlist_url(line):
            print(f"Fetching playlist: {line}")
            for item in get_playlist_videos(line):
                if isinstance(item, str):
                    video_ids.append(item)
                else:
                    # It's an error tuple
                    _, _, error = item
                    print(f"  Error: {error}")
            print(f"  Found {len(video_ids)} videos so far")
        else:
            video_ids.append(line)

    return video_ids


def main():
    parser = argparse.ArgumentParser(
        description="Estimate disk space for YouTube videos in 480p quality"
    )
    parser.add_argument(
        'file',
        nargs='?',
        type=argparse.FileType('r'),
        default=sys.stdin,
        help='File containing video IDs (JSON array) or playlist URLs (one per line)'
    )
    parser.add_argument(
        '-q', '--quality',
        default="480",
        help='Video quality/height (default: 480)'
    )
    parser.add_argument(
        '-p', '--parallel',
        type=int,
        default=1,
        help='Number of parallel requests (default: 1, max: 5)'
    )
    parser.add_argument(
        '-o', '--output',
        type=str,
        help='Save report to file'
    )
    args = parser.parse_args()

    # Limit parallel to avoid rate limiting
    parallel = min(args.parallel, 5)

    # Process input to get video IDs
    video_ids = process_input(args.file)

    if not video_ids:
        print("No video IDs found in input")
        sys.exit(1)

    print(f"\nFound {len(video_ids)} video IDs")
    print(f"Estimating disk space for {args.quality}p downloads...\n")

    total_size = 0
    successful = 0
    failed = 0
    results = []

    if parallel > 1:
        # Parallel processing
        with ThreadPoolExecutor(max_workers=parallel) as executor:
            futures = {
                executor.submit(get_video_size, vid, args.quality): vid
                for vid in video_ids
            }

            for i, future in enumerate(as_completed(futures), 1):
                video_id = futures[future]
                print(f"[{i}/{len(video_ids)}] Processing {video_id}...", end=" ", flush=True)

                size, title, error = future.result()

                if error:
                    print(f"FAILED: {error}")
                    failed += 1
                    results.append({'id': video_id, 'error': error})
                else:
                    print(f"{format_size(size)} - {title}")
                    total_size += size
                    successful += 1
                    results.append({'id': video_id, 'title': title, 'size': size})

                if i % 10 == 0:
                    print(f"\n--- Running total: {format_size(total_size)} ({successful} successful, {failed} failed) ---\n")
    else:
        # Sequential processing
        for i, video_id in enumerate(video_ids, 1):
            print(f"[{i}/{len(video_ids)}] Processing {video_id}...", end=" ", flush=True)

            size, title, error = get_video_size(video_id, quality=args.quality)

            if error:
                print(f"FAILED: {error}")
                failed += 1
                results.append({'id': video_id, 'error': error})
            else:
                print(f"{format_size(size)} - {title}")
                total_size += size
                successful += 1
                results.append({'id': video_id, 'title': title, 'size': size})

            if i % 10 == 0:
                print(f"\n--- Running total: {format_size(total_size)} ({successful} successful, {failed} failed) ---\n")

    # Final summary
    summary = f"""
{'='*70}
SUMMARY
{'='*70}
Total videos: {len(video_ids)}
Successful: {successful}
Failed: {failed}

Estimated total disk space ({args.quality}p): {format_size(total_size)}
{'='*70}
"""
    print(summary)

    # Save report if requested
    if args.output:
        report = {
            'quality': args.quality,
            'total_videos': len(video_ids),
            'successful': successful,
            'failed': failed,
            'total_size_bytes': total_size,
            'total_size_human': format_size(total_size),
            'videos': results
        }
        with open(args.output, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"Report saved to: {args.output}")


if __name__ == "__main__":
    main()
