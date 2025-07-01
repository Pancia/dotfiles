import os
import re
import datetime
from collections import defaultdict
import matplotlib.pyplot as plt
import pandas as pd
import glob
import argparse

class ActivityAnalyzer:
    def __init__(self):
        # Activity categories with associated keywords
        self.categories = {
            'YouTube': ['YouTube', 'youtube.com'],
            'Development': ['nvim', 'vim', 'vscode', 'code', 'iTerm', 'terminal', 'firefox-extension', 'github'],
            'Entertainment': ['Netflix', 'Spotify', 'game', 'movie', 'tv', 'show', 'video'],
            'Social': ['Telegram', 'Signal', 'WhatsApp', 'Discord', 'Slack'],
            'Browsing': ['Zen', 'Firefox', 'Chrome', 'Safari', 'Edge', 'moz-extension'],
            'Productivity': ['Notes', 'Calendar', 'Mail', 'Gmail', 'Dropbox', 'Google Doc', 'Excel', 'Sheet'],
            'Audio': ['Audacity', 'ffmpeg', 'audio', 'wav', 'mp3'],
            'File Management': ['Finder', 'Files', 'Downloads']
        }

        # Browser apps for more detailed analysis
        self.browser_apps = ['Firefox', 'Chrome', 'Safari', 'Edge', 'Zen']

        # Website domains and their categories
        self.website_categories = {
            'youtube.com': 'YouTube',
            'github.com': 'Development',
            'stackoverflow.com': 'Development',
            'netflix.com': 'Entertainment',
            'spotify.com': 'Entertainment',
            'gmail.com': 'Productivity',
            'docs.google.com': 'Productivity',
            'drive.google.com': 'Productivity',
            'twitter.com': 'Social',
            'reddit.com': 'Social',
            'instagram.com': 'Social',
            'facebook.com': 'Social',
            'linkedin.com': 'Professional'
        }

        # Special categories that override others
        self.special_categories = {
            'YouTube': ['YouTube'],
            'Sleeping': ['SLEEPING']
        }

        # Initialize data structures
        self.activities = []
        self.detailed_activities = []  # Store detailed activity records
        self.time_by_category = defaultdict(int)
        self.time_by_app = defaultdict(int)
        self.time_by_website = defaultdict(int)  # Track time by website domain
        self.time_by_hour = defaultdict(int)
        self.time_by_day = defaultdict(int)
        self.time_spent_by_category_by_day = defaultdict(lambda: defaultdict(int))

    def parse_log_file(self, file_path):
        """Parse a single log file and extract activities"""
        with open(file_path, 'r') as file:
            content = file.read()

        # Extract timestamp, app, and details from log entries
        pattern = r'NOW: (\d{4}_\d{2}_\d{2}__\d{2}:\d{2}:\d{2})\nFOCUSED: ([^=]+) => ([^\n]+)'
        matches = re.findall(pattern, content)

        sleeping_pattern = r'NOW: (\d{4}_\d{2}_\d{2}__\d{2}:\d{2}:\d{2})\n<(SLEEPING)>'
        sleeping_matches = re.findall(sleeping_pattern, content)

        nochange_pattern = r'NOW: (\d{4}_\d{2}_\d{2}__\d{2}:\d{2}:\d{2})\n<NOCHANGE FOCUSED: ([^=]+) => ([^\n>]+)>'
        nochange_matches = re.findall(nochange_pattern, content)

        # Combine all matches
        all_activities = []

        for timestamp, app, details in matches:
            all_activities.append((timestamp, app, details))

        for timestamp, state in sleeping_matches:
            all_activities.append((timestamp, state, ""))

        for timestamp, app, details in nochange_matches:
            all_activities.append((timestamp, app, details))

        # Sort activities by timestamp
        all_activities.sort(key=lambda x: x[0])

        # Add to the main activities list
        self.activities.extend(all_activities)

    def parse_log_directory(self, directory_path):
        """Parse all log files in a directory"""
        log_files = glob.glob(os.path.join(directory_path, "*.log"))
        for log_file in sorted(log_files):
            self.parse_log_file(log_file)

    def calculate_durations(self):
        """Calculate durations for each activity"""
        if not self.activities:
            return

        # Sort activities by timestamp
        self.activities.sort(key=lambda x: x[0])

        # Format for parsing log file timestamps
        time_format = "%Y_%m_%d__%H:%M:%S"

        # Process each activity entry
        for i in range(len(self.activities) - 1):
            current_timestamp, current_app, current_details = self.activities[i]
            next_timestamp, _, _ = self.activities[i + 1]

            # Parse timestamps
            current_time = datetime.datetime.strptime(current_timestamp, time_format)
            next_time = datetime.datetime.strptime(next_timestamp, time_format)

            # Calculate duration in minutes
            duration = (next_time - current_time).total_seconds() / 60

            # Skip if more than 30 minutes between logs (likely inactive)
            if duration > 30:
                continue

            # Add duration to category counters
            category = self.categorize_activity(current_app, current_details)
            self.time_by_category[category] += duration

            # Track by app
            self.time_by_app[current_app] += duration

            # Track website information for browsers
            if any(browser in current_app for browser in self.browser_apps):
                domain = self.extract_website_domain(current_details)
                if domain != "unknown":
                    self.time_by_website[domain] += duration

                    # Add detailed activity record for later analysis
                    self.detailed_activities.append({
                        'timestamp': current_timestamp,
                        'datetime': current_time.isoformat(),
                        'app': current_app,
                        'website': domain if domain != "unknown" else None,
                        'title': current_details,
                        'category': category,
                        'duration': duration
                    })
            else:
                # Add detailed activity record for non-browser apps
                self.detailed_activities.append({
                    'timestamp': current_timestamp,
                    'datetime': current_time.isoformat(),
                    'app': current_app,
                    'title': current_details,
                    'category': category,
                    'duration': duration
                })

            # Track by hour of day
            hour = current_time.hour
            self.time_by_hour[hour] += duration

            # Track by day
            day = current_time.strftime("%Y-%m-%d")
            self.time_by_day[day] += duration

            # Track category by day
            self.time_spent_by_category_by_day[day][category] += duration

    def categorize_activity(self, app, details):
        """Categorize an activity based on app name and details"""
        # Special case for sleeping
        if app == "SLEEPING":
            return "Sleeping"

        # Check special categories first (these override the general categories)
        for category, keywords in self.special_categories.items():
            for keyword in keywords:
                if keyword in details or keyword in app:
                    return category

        # Special handling for browsers - check the website domain from details
        if any(browser in app for browser in self.browser_apps):
            # Extract domain from browser window title
            for domain, category in self.website_categories.items():
                if domain in details.lower():
                    return category

        # Check general categories
        for category, keywords in self.categories.items():
            for keyword in keywords:
                if keyword in details or keyword in app:
                    return category

        # Default category
        return "Other"

    def extract_website_domain(self, details):
        """Extract website domain from a browser window title"""
        # Match common domain patterns
        domain_pattern = r'(?:https?://)?(?:www\.)?([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})(?:/|$| |-)'
        match = re.search(domain_pattern, details.lower())

        if match:
            return match.group(1)

        # Some common sites might appear in titles without URLs
        common_sites = {
            'youtube': 'youtube.com',
            'github': 'github.com',
            'google': 'google.com',
            'stackoverflow': 'stackoverflow.com',
            'reddit': 'reddit.com'
        }

        for site_name, domain in common_sites.items():
            if site_name in details.lower():
                return domain

        return "unknown"

    def generate_summary(self):
        """Generate summary statistics"""
        total_time = sum(self.time_by_category.values())

        print("\n--- ACTIVITY SUMMARY ---")
        print(f"Total time tracked: {total_time:.2f} minutes ({total_time/60:.2f} hours)")
        print("\nTime by category:")

        # Sort categories by time spent
        sorted_categories = sorted(self.time_by_category.items(), key=lambda x: x[1], reverse=True)

        for category, duration in sorted_categories:
            percentage = (duration / total_time) * 100 if total_time > 0 else 0
            print(f"  {category}: {duration:.2f} minutes ({percentage:.1f}%)")

        # Top applications
        print("\nTop 10 applications:")
        sorted_apps = sorted(self.time_by_app.items(), key=lambda x: x[1], reverse=True)[:10]
        for app, duration in sorted_apps:
            percentage = (duration / total_time) * 100 if total_time > 0 else 0
            print(f"  {app}: {duration:.2f} minutes ({percentage:.1f}%)")

        # Top websites
        if self.time_by_website:
            print("\nTop 10 websites:")
            sorted_websites = sorted(self.time_by_website.items(), key=lambda x: x[1], reverse=True)[:10]
            for website, duration in sorted_websites:
                percentage = (duration / total_time) * 100 if total_time > 0 else 0
                print(f"  {website}: {duration:.2f} minutes ({percentage:.1f}%)")

    def visualize_data(self, output_dir="."):
        """Create visualizations of the data"""
        if not os.path.exists(output_dir):
            os.makedirs(output_dir)

        # 1. Pie chart for category distribution
        plt.figure(figsize=(10, 6))
        categories = list(self.time_by_category.keys())
        values = list(self.time_by_category.values())

        # Filter out small categories for cleaner visualization
        threshold = sum(values) * 0.03  # 3% threshold
        other_sum = 0

        filtered_categories = []
        filtered_values = []

        for i, value in enumerate(values):
            if value >= threshold:
                filtered_categories.append(categories[i])
                filtered_values.append(value)
            else:
                other_sum += value

        if other_sum > 0:
            filtered_categories.append('Other')
            filtered_values.append(other_sum)

        plt.pie(filtered_values, labels=filtered_categories, autopct='%1.1f%%', startangle=90)
        plt.axis('equal')
        plt.title('Time Distribution by Category')
        plt.savefig(os.path.join(output_dir, 'category_distribution.png'))

        # 2. Bar chart for time by hour of day
        plt.figure(figsize=(12, 6))
        hours = sorted(self.time_by_hour.keys())
        hour_values = [self.time_by_hour[hour] for hour in hours]

        plt.bar(hours, hour_values)
        plt.xlabel('Hour of Day')
        plt.ylabel('Minutes')
        plt.title('Activity by Hour of Day')
        plt.xticks(range(0, 24))
        plt.grid(axis='y', linestyle='--', alpha=0.7)
        plt.savefig(os.path.join(output_dir, 'activity_by_hour.png'))

        # 3. Line chart for activity over days
        if self.time_by_day:
            plt.figure(figsize=(12, 6))
            days = sorted(self.time_by_day.keys())
            day_values = [self.time_by_day[day]/60 for day in days]  # Convert to hours

            plt.plot(days, day_values, marker='o')
            plt.xlabel('Date')
            plt.ylabel('Hours')
            plt.title('Activity Hours by Day')
            plt.xticks(rotation=45)
            plt.grid(True, linestyle='--', alpha=0.7)
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'activity_by_day.png'))

        # 4. Stacked area chart for categories over time
        if self.time_spent_by_category_by_day:
            # Convert to DataFrame for easier plotting
            data = []
            days = sorted(self.time_spent_by_category_by_day.keys())

            for day in days:
                day_data = {'date': day}
                for category, time in self.time_spent_by_category_by_day[day].items():
                    day_data[category] = time / 60  # Convert to hours
                data.append(day_data)

            df = pd.DataFrame(data)
            df.set_index('date', inplace=True)

            # Fill NaN values with 0
            df.fillna(0, inplace=True)

            # Plot
            plt.figure(figsize=(12, 6))
            df.plot.area(figsize=(12, 6), alpha=0.7)
            plt.xlabel('Date')
            plt.ylabel('Hours')
            plt.title('Time Spent by Category Over Time')
            plt.grid(True, linestyle='--', alpha=0.5)
            plt.legend(loc='center left', bbox_to_anchor=(1, 0.5))
            plt.tight_layout()
            plt.savefig(os.path.join(output_dir, 'categories_over_time.png'))

        print(f"\nVisualizations saved to: {output_dir}")

    def generate_insights(self):
        """Generate insights from the data"""
        print("\n--- INSIGHTS ---")

        # Calculate productive vs entertainment time
        productive_categories = ['Development', 'Productivity']
        entertainment_categories = ['YouTube', 'Entertainment']

        productive_time = sum(self.time_by_category[cat] for cat in productive_categories if cat in self.time_by_category)
        entertainment_time = sum(self.time_by_category[cat] for cat in entertainment_categories if cat in self.time_by_category)

        if productive_time + entertainment_time > 0:
            ratio = productive_time / (productive_time + entertainment_time)
            print(f"Productivity ratio: {ratio:.2f} ({productive_time/60:.1f} hours productive vs {entertainment_time/60:.1f} hours entertainment)")

        # Most active times
        if self.time_by_hour:
            most_active_hour = max(self.time_by_hour.items(), key=lambda x: x[1])
            print(f"Most active hour: {most_active_hour[0]}:00 ({most_active_hour[1]/60:.1f} hours total)")

            morning_time = sum(self.time_by_hour.get(h, 0) for h in range(5, 12))
            afternoon_time = sum(self.time_by_hour.get(h, 0) for h in range(12, 17))
            evening_time = sum(self.time_by_hour.get(h, 0) for h in range(17, 22))
            night_time = sum(self.time_by_hour.get(h, 0) for h in range(22, 24)) + sum(self.time_by_hour.get(h, 0) for h in range(0, 5))

            print(f"Time distribution throughout the day:")
            print(f"  Morning (5am-12pm): {morning_time/60:.1f} hours")
            print(f"  Afternoon (12pm-5pm): {afternoon_time/60:.1f} hours")
            print(f"  Evening (5pm-10pm): {evening_time/60:.1f} hours")
            print(f"  Night (10pm-5am): {night_time/60:.1f} hours")

        # Top specific activities
        if self.activities:
            # Extract more specific activities from details
            specific_activities = defaultdict(int)

            # Use the detailed_activities list that's already populated
            for activity in self.detailed_activities:
                if "YouTube" in activity['category']:
                    if activity['title']:
                        video_title = activity['title'].replace(" - YouTube", "")
                        specific_activities[f"YouTube: {video_title}"] += activity['duration']
                elif "Development" in activity['category']:
                    if "/" in activity.get('title', ''):
                        parts = activity['title'].split("/")
                        if len(parts) > 1:
                            project = parts[1].split(" ")[0]
                            specific_activities[f"Project: {project}"] += activity['duration']

            print("\nTop specific activities:")
            top_specific = sorted(specific_activities.items(), key=lambda x: x[1], reverse=True)[:5]
            for activity, duration in top_specific:
                print(f"  {activity}: {duration:.2f} minutes ({duration/60:.1f} hours)")

    def export_activity_data(self, output_file):
        """Export detailed activity data to JSON for LLM analysis"""
        import json

        # Create a structured data object for export
        export_data = {
            "metadata": {
                "total_time_minutes": sum(self.time_by_category.values()),
                "date_range": {
                    "start": min(self.time_by_day.keys()) if self.time_by_day else None,
                    "end": max(self.time_by_day.keys()) if self.time_by_day else None
                },
                "exported_at": datetime.datetime.now().isoformat()
            },
            "summary": {
                "time_by_category": {k: round(v, 2) for k, v in self.time_by_category.items()},
                "time_by_app": {k: round(v, 2) for k, v in sorted(self.time_by_app.items(), key=lambda x: x[1], reverse=True)[:20]},
                "time_by_website": {k: round(v, 2) for k, v in sorted(self.time_by_website.items(), key=lambda x: x[1], reverse=True)[:20]}
            }
        }

        # Export to file
        with open(output_file, 'w') as f:
            json.dump(export_data, f, indent=2)

        print(f"\nExported detailed activity data to: {output_file}")
        print("This file can be used for LLM analysis to generate categories and tags.")


def main():
    parser = argparse.ArgumentParser(description='Analyze activity logs and generate insights')
    parser.add_argument('path', help='Path to a log file or directory containing log files')
    parser.add_argument('--output', '-o', default='.', help='Output directory for visualizations')
    parser.add_argument('--export', '-e', default=None, help='Export detailed activity data to JSON file for LLM analysis')

    args = parser.parse_args()

    analyzer = ActivityAnalyzer()

    if os.path.isdir(args.path):
        analyzer.parse_log_directory(args.path)
    else:
        analyzer.parse_log_file(args.path)

    analyzer.calculate_durations()
    analyzer.generate_summary()
    analyzer.generate_insights()
    analyzer.visualize_data(args.output)

    # Export detailed activity data if requested
    if args.export:
        export_path = args.export
        if not export_path.endswith('.json'):
            export_path += '.json'
        analyzer.export_activity_data(export_path)


if __name__ == "__main__":
    main()
