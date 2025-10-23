#!/usr/bin/env python3
"""
Estimate disk space required to download YouTube videos in 480p quality.
Reads video IDs from a file or stdin and uses yt-dlp to get size estimates.
"""

import json
import subprocess
import sys
import argparse
from pathlib import Path


def get_video_size(video_id, quality="480"):
    """
    Get estimated file size for a YouTube video at specified quality.

    Args:
        video_id: YouTube video ID
        quality: Desired height resolution (default: 480)

    Returns:
        Tuple of (size_in_bytes, title, error_message)
    """
    url = f"https://www.youtube.com/watch?v={video_id}"

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


def main():
    parser = argparse.ArgumentParser(
        description="Estimate disk space for YouTube videos in 480p quality"
    )
    parser.add_argument(
        'file',
        nargs='?',
        type=argparse.FileType('r'),
        default=sys.stdin,
        help='JSON file containing video IDs (reads from stdin if not provided)'
    )
    args = parser.parse_args()

    # Read video IDs from file or stdin
    try:
        video_ids = json.load(args.file)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON input - {e}")
        sys.exit(1)

    print(f"Found {len(video_ids)} video IDs")
    print(f"Estimating disk space for 480p downloads...\n")

    total_size = 0
    successful = 0
    failed = 0

    for i, video_id in enumerate(video_ids, 1):
        print(f"[{i}/{len(video_ids)}] Processing {video_id}...", end=" ")

        size, title, error = get_video_size(video_id, quality="480")

        if error:
            print(f"❌ FAILED: {error}")
            failed += 1
        else:
            print(f"✓ {format_size(size)}")
            if title:
                print(f"    Title: {title}")
            total_size += size
            successful += 1

        # Print running total every 10 videos
        if i % 10 == 0:
            print(f"\n--- Running total: {format_size(total_size)} ({successful} successful, {failed} failed) ---\n")

    # Final summary
    print("\n" + "="*70)
    print("SUMMARY")
    print("="*70)
    print(f"Total videos: {len(video_ids)}")
    print(f"Successful: {successful}")
    print(f"Failed: {failed}")
    print(f"\nEstimated total disk space (480p): {format_size(total_size)}")
    print("="*70)


if __name__ == "__main__":
    main()
