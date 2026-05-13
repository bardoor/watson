import shutil
import subprocess
from pathlib import Path


class WhisperError(RuntimeError):
    pass


def transcribe(
    audio_path: Path,
    output_dir: Path,
    output_name: str,
    language: str,
    model: str,
) -> Path:
    """
    Runs mlx-whisper as a subprocess.
    """
    mlx_whisper = shutil.which("mlx_whisper")
    if not mlx_whisper:
        raise WhisperError(
            "mlx_whisper not found. Try: uv sync, then run through uv run watson ..."
        )

    cmd = [
        mlx_whisper,
        str(audio_path),
        "--model",
        model,
        "--language",
        language,
        "--output-dir",
        str(output_dir),
        "--output-name",
        output_name,
        "-f",
        "all",
    ]

    subprocess.run(cmd, check=True)

    transcript_txt = output_dir / f"{output_name}.txt"
    if not transcript_txt.exists():
        raise WhisperError(
            f"mlx-whisper finished, but {output_name}.txt was not created."
        )

    return transcript_txt
