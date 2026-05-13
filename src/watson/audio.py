import shutil
import subprocess
from pathlib import Path


class AudioError(RuntimeError):
    pass


def _require_ffmpeg() -> str:
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        raise AudioError("ffmpeg is not installed. Run: brew install ffmpeg")
    return ffmpeg


def prepare_mic_for_whisper(
    input_audio: Path,
    output_audio: Path,
) -> Path | None:
    """
    Prepares microphone audio for Whisper.

    Important:
    - do not remove silence
    - do not change duration
    - avoid dynaudnorm because it can raise noise floor and cause Whisper "..."
    """
    if not input_audio.exists() or input_audio.stat().st_size == 0:
        return None

    ffmpeg = _require_ffmpeg()

    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(input_audio),
        "-af",
        "highpass=f=80,"
        "acompressor=threshold=-20dB:ratio=2:attack=20:release=250:makeup=2dB,"
        "loudnorm=I=-18:TP=-2:LRA=11",
        "-ac",
        "1",
        "-ar",
        "16000",
        str(output_audio),
    ]

    subprocess.run(cmd, check=True)

    if not output_audio.exists() or output_audio.stat().st_size == 0:
        raise AudioError("ffmpeg did not create mic_whisper.wav")

    return output_audio


def prepare_system_for_whisper(
    input_audio: Path,
    output_audio: Path,
) -> Path | None:
    """
    Prepares system audio for Whisper.

    Important:
    - do not remove silence
    - do not change duration
    - keep processing gentle
    """
    if not input_audio.exists() or input_audio.stat().st_size == 0:
        return None

    ffmpeg = _require_ffmpeg()

    cmd = [
        ffmpeg,
        "-y",
        "-i",
        str(input_audio),
        "-af",
        "acompressor=threshold=-18dB:ratio=1.8:attack=15:release=200:makeup=1.5dB,"
        "loudnorm=I=-18:TP=-2:LRA=11",
        "-ac",
        "1",
        "-ar",
        "16000",
        str(output_audio),
    ]

    subprocess.run(cmd, check=True)

    if not output_audio.exists() or output_audio.stat().st_size == 0:
        raise AudioError("ffmpeg did not create system_whisper.wav")

    return output_audio


def create_mixed_preview(
    mic_audio: Path,
    system_audio: Path,
    output_audio: Path,
) -> Path | None:
    """
    Creates a mixed audio file only for listening/debugging.

    This is intentionally not the primary Whisper input.
    """
    ffmpeg = _require_ffmpeg()

    inputs = [p for p in [mic_audio, system_audio] if p.exists() and p.stat().st_size > 0]

    if not inputs:
        return None

    if len(inputs) == 1:
        cmd = [
            ffmpeg,
            "-y",
            "-i",
            str(inputs[0]),
            "-ac",
            "2",
            "-ar",
            "48000",
            str(output_audio),
        ]
    else:
        cmd = [
            ffmpeg,
            "-y",
            "-i",
            str(mic_audio),
            "-i",
            str(system_audio),
            "-filter_complex",
            "[0:a]volume=1.3[mic];"
            "[1:a]volume=0.9[sys];"
            "[mic][sys]amix=inputs=2:duration=longest:normalize=0[out]",
            "-map",
            "[out]",
            "-ac",
            "2",
            "-ar",
            "48000",
            str(output_audio),
        ]

    subprocess.run(cmd, check=True)

    if not output_audio.exists() or output_audio.stat().st_size == 0:
        raise AudioError("ffmpeg did not create mixed_preview.wav")

    return output_audio
