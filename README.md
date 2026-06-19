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
* macOS 15+
* Apple Silicon recommended
* Elixir 1.17+
* Erlang / OTP 28+
* Swift / Xcode Command Line Tools
* `mlx_whisper` available in `PATH`

### Install dependencies

Install Xcode tools:

```bash
xcode-select --install
```

Install Elixir and ffmpeg:

```bash
brew install elixir ffmpeg
```

Install `mlx_whisper` the way you prefer. Example:

```bash
pip install mlx-whisper
```

If the binary is not in `PATH`, set `WATSON_MLX_WHISPER_PATH`.

### Build
```bash
cd native/macos_recorder
swift build -c release
cd ../..
mix deps.get
mix escript.build
```

### Run

List microphones:

```bash
./watson devices
```

Record in Russian:

```bash
./watson record --language ru
```

Record in English:

```bash
./watson record --language en
```

Stop recording with `Enter`.

You can also override runtime paths through env vars:

```bash
WATSON_HELPER_PATH=/absolute/path/to/watson-recorder \
WATSON_MLX_WHISPER_PATH=/absolute/path/to/mlx_whisper \
WATSON_RECORDINGS_DIR=/absolute/path/to/recordings \
./watson record
```

### Output

Each run creates a new session in:

```bash
recordings/<timestamp>/
```

Example:

```bash
recordings/2026-05-13_00-21-48/
  mic.wav
  system.wav
  mic_transcript.partial.txt
  system_transcript.partial.txt
  mic_transcript.txt
  system_transcript.txt
  mic_transcript.tsv
  system_transcript.tsv
  mic_transcript.cleaned.txt
  mic_transcript.cleaned.tsv
  system_transcript.cleaned.txt
  system_transcript.cleaned.tsv
  dialogue_transcript.txt
  dialogue_transcript.tsv
```

### macOS permissions

On first run, macOS will ask for:

* Microphone permission
* Screen Recording permission

Screen Recording permission is required for system audio capture.

Watson does not save video frames.

Notes
* microphone and system audio are transcribed separately
* audio is persisted incrementally during the session
* partial transcripts are produced from rolling `mlx_whisper` snapshots
* cleaned transcripts remove empty segments, invalid timestamps, punctuation-only noise, known subtitle noise, and repeated text after its first occurrence
* dialogue_transcript.txt merges cleaned microphone and system transcripts in chronological order
* all transcription runs locally through mlx-whisper
