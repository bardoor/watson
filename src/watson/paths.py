from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


@dataclass(frozen=True)
class SessionPaths:
    session_dir: Path

    mic_audio: Path
    system_audio: Path

    mic_whisper_audio: Path
    system_whisper_audio: Path
    mixed_preview_audio: Path

    mic_transcript_txt: Path
    system_transcript_txt: Path


def create_session_paths(output_dir: Path) -> SessionPaths:
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    session_dir = output_dir / timestamp
    session_dir.mkdir(parents=True, exist_ok=False)

    return SessionPaths(
        session_dir=session_dir,

        mic_audio=session_dir / "mic.m4a",
        system_audio=session_dir / "system.m4a",

        mic_whisper_audio=session_dir / "mic_whisper.wav",
        system_whisper_audio=session_dir / "system_whisper.wav",
        mixed_preview_audio=session_dir / "mixed_preview.wav",

        mic_transcript_txt=session_dir / "mic_transcript.txt",
        system_transcript_txt=session_dir / "system_transcript.txt",
    )
