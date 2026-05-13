# Watson

Watson is a local macOS recording + transcription tool.

It records:

* microphone audio
* system audio via ScreenCaptureKit

Then transcribes both tracks separately using `mlx-whisper`.

No cloud APIs.
No screen video recording.
Audio only.

### Requirements
* macOS 13+
* Apple Silicon recommended
* Python 3.11+
* Swift / Xcode Command Line Tools
* Homebrew

### Install dependencies

Install Xcode tools:

```bash
xcode-select --install
```

Install uv and ffmpeg:

```bash
brew install uv ffmpeg
Install Python dependencies
uv sync
```

### Build native recorder
```bash
cd native/macos_recorder
swift build -c release
cd ../..
```

### Run

Russian:

```bash
uv run watson --language ru
```

English:

```bash
uv run watson --language en
```

Stop recording with:

```bash
Ctrl+C
```

### Output

Each run creates a new session in:

```bash
recordings/<timestamp>/
```

Example:

```bash
recordings/2026-05-13_00-21-48/
  mic.m4a
  system.m4a

  mic_whisper.wav
  system_whisper.wav
  mixed_preview.wav

  mic_transcript.txt
  system_transcript.txt
```

### macOS permissions

On first run, macOS will ask for:

* Microphone permission
* Screen Recording permission

Screen Recording permission is required for system audio capture.

Watson does not save video frames.

Notes
* microphone and system audio are transcribed separately
* tracks keep the same duration
* mixed_preview.wav is only for listening/debugging
* all transcription runs locally through mlx-whisper
