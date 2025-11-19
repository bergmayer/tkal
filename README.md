# tkal

A native Swift terminal calendar for macOS using EventKit.

## Features

- Native Swift implementation using macOS EventKit
- Terminal-based calendar interface
- Direct integration with macOS Calendar
- Interactive TUI mode with ncurses
- Simple interactive mode with command prompt
- Command-line calendar management

## Requirements

- macOS 12.0 or later
- Swift toolchain

## Installation

```bash
./install.sh
```

Or manually:

```bash
swift build -c release
sudo cp .build/release/tkal /usr/local/bin/
```

## Usage

### Quick Start

```bash
# Show current events
tkal

# Launch full interactive TUI mode
tkal --interactive

# Launch simple interactive mode
tkal --simple
```

### Basic Commands

```bash
# List events
tkal list --days 7
tkal list --week

# Create new event
tkal new tomorrow 3pm Meeting with team
tkal new 2025-01-15 10am 11am Project Review

# Search events
tkal search meeting

# Show calendar
tkal calendar

# List calendars
tkal calendars
```

### Interactive Modes

tkal offers two interactive modes:

#### Full Interactive TUI Mode (`--interactive` or `-i`)

Full-screen ncurses interface with calendar view and event browser.

```bash
tkal --interactive
# or
tkal -i
# or as subcommand
tkal interactive
```

**Navigation:**
- `Tab` - Switch between calendar and events
- `Arrow keys` or `hjkl` - Navigate
- `Enter` - View event details
- `Left` - Back to calendar

**Actions:**
- `n` - Create new event
- `/` - Search events
- `t` - Jump to today
- `r` - Refresh events
- `c` - Toggle calendars on/off
- `Shift+T` - Toggle 12/24 hour time format
- `?` - Show help
- `q` - Quit

#### Simple Interactive Mode (`--simple` or `-s`)

Text-based command prompt interface for quick event management.

```bash
tkal --simple
# or
tkal -s
```

**Available commands at the `tkal>` prompt:**
- `t` or `today` - Show today's events
- `w` or `week` - Show this week's events
- `n` or `new` - Create a new event (with prompts)
- `s` or `search` - Search events
- `l` or `list` - List calendars
- `h` or `help` - Show help
- `q` or `quit` - Exit

### Date Format Examples

```bash
tkal new tomorrow 3pm Team Meeting
tkal new "next friday" 2pm Project Review
tkal new 2025-01-15 10am Conference Call
```

## Configuration

Config stored at `~/.config/tkal/config.json`

## Permissions

On first run, macOS will request Calendar access permissions.

Grant via: **System Settings > Privacy & Security > Calendars**

## License

This software is released into the public domain under the Unlicense. See LICENSE file for details.
