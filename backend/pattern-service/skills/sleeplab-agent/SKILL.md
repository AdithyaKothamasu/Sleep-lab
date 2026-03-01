---
name: sleeplab-agent
description: >
  Query your SleepLab sleep data securely. Retrieves sleep metrics including 
  sleep stages, heart rate, HRV, respiratory rate, workouts, and behavior 
  logs from your paired SleepLab iOS app.
---

# SleepLab Agent Skill

You have access to the user's SleepLab sleep tracking data via a REST API.

## Setup

The connection code is stored in `{baseDir}/.env`. It has the format:

```
SLEEPLAB_API_KEY=slk_...
SLEEPLAB_API_URL=https://...
```

If the `.env` file does not exist or is empty, ask the user to:
1. Open the SleepLab app → Settings → "Connect AI Agent"
2. Tap "Copy Connection Code"
3. Paste the code here in the chat

When the user pastes a connection code like `sleeplab://connect/<key>@<url>`, parse it and save:
- Extract the API key (between `/connect/` and `@`)
- Extract the URL (after `@`)
- Write them to `{baseDir}/.env`
- Confirm: "✅ Connected to SleepLab! Try asking me how you slept last night."

## Available Endpoints

Use the `exec` tool with `curl` to call these endpoints. Always include the API key header.

### Get Recent Sleep Data
```bash
curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$SLEEPLAB_API_URL/v1/data/sleep?days=7"
```
Returns the last N days (1-30) of sleep summaries including total sleep hours, sleep stages, heart rate, HRV, respiratory rate, and workout minutes.

### Get Sleep Data for a Specific Date
```bash
curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$SLEEPLAB_API_URL/v1/data/sleep/2026-02-27"
```
Returns full details for a specific day including all sleep segments with timestamps, plus behavior events.

### Get Sleep Data for a Date Range
```bash
curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$SLEEPLAB_API_URL/v1/data/sleep/range?from=2026-02-20&to=2026-02-27"
```
Returns full details for all days between the start and end date (inclusive). Use this for querying a week's or month's worth of data.

### Get Aggregated Stats
```bash
curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$SLEEPLAB_API_URL/v1/data/sleep/stats?days=14"
```
Returns computed averages over the last N days: average sleep duration, HRV, heart rate, respiratory rate, stage durations, etc.

### Get Behavior Events
```bash
curl -s -H "Authorization: Bearer $SLEEPLAB_API_KEY" "$SLEEPLAB_API_URL/v1/data/events?days=7"
```
Returns behavior logs (caffeine intake, workouts, dinner timing, etc.) for the last N days.

## Reading the .env File

Before making any API call, read the env file:
```bash
source {baseDir}/.env
```

If the file doesn't exist, ask the user to set up the connection first.

## Data Format

All responses are JSON. Sleep data includes:
- **totalSleepHours**: Total time asleep (excluding awake periods)
- **awakeningCount**: Number of times woken up
- **mainSleepStartISO / mainSleepEndISO**: When the main sleep window started/ended
- **averageHeartRate**: Average heart rate during sleep (bpm)
- **averageHRV**: Heart rate variability SDNN (ms) — higher is generally better
- **averageRespiratoryRate**: Breathing rate (breaths/min)
- **workoutMinutes**: Total exercise duration that day
- **stageDurations**: Time spent in each sleep stage (deep, core, REM, awake) in hours
- **segments**: Individual sleep stage segments with start/end timestamps
- **events**: Behavior logs like caffeine, dinner, workouts with timestamps

## Response Guidelines

When discussing sleep data with the user:
- Use plain language, not technical jargon
- Highlight notable patterns (e.g., "You got more deep sleep on days you worked out")
- Compare to general healthy ranges when relevant (e.g., 7-9 hours total, 1-2 hours deep sleep)
- If HRV data is available, note that higher HRV generally indicates better recovery
- Always mention if data seems incomplete or missing for requested dates
