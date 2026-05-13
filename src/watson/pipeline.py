import subprocess
from dataclasses import dataclass
from pathlib import Path

from watson.audio import (
    create_mixed_preview,
    prepare_mic_for_whisper,
    prepare_system_for_whisper,
)
from watson.paths import create_session_paths
from watson.whisper import transcribe


@dataclass(frozen=True)
class PipelineResult:
    session_dir: Path
    mic_whisper_audio: Path | None
    system_whisper_audio: Path | None
    mixed_preview_audio: Path | None
    mic_transcript_txt: Path | None
    system_transcript_txt: Path | None


def record_and_transcribe(
    language: str,
    model: str,
    output_dir: Path,
) -> PipelineResult:
    paths = create_session_paths(output_dir)

    recorder_bin = Path("native/macos_recorder/.build/release/watson-recorder")

    if not recorder_bin.exists():
        raise RuntimeError(
            "Native recorder is not built.\n"
            "Run:\n"
            "  cd native/macos_recorder\n"
            "  swift build -c release\n"
            "  cd ../.."
        )

    print(f"Session: {paths.session_dir}")
    print("Starting recorder...")
    print("Stop recording with Ctrl+C.")
    print("")

    process = subprocess.Popen(
        [
            str(recorder_bin),
            "--output-dir",
            str(paths.session_dir),
        ],
        stdin=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )

    try:
        process.wait()
    except KeyboardInterrupt:
        print("")
        print("Stopping recorder...")

        if process.poll() is None and process.stdin:
            try:
                process.stdin.write("stop\n")
                process.stdin.flush()
                process.stdin.close()
            except BrokenPipeError:
                pass

        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            print("Recorder did not stop gracefully, terminating...")
            process.terminate()
            process.wait(timeout=5)

    if process.returncode not in (0, None):
        raise RuntimeError(f"Recorder exited with code {process.returncode}")

    print("Preparing microphone audio...")
    mic_whisper_audio = prepare_mic_for_whisper(
        input_audio=paths.mic_audio,
        output_audio=paths.mic_whisper_audio,
    )

    print("Preparing system audio...")
    system_whisper_audio = prepare_system_for_whisper(
        input_audio=paths.system_audio,
        output_audio=paths.system_whisper_audio,
    )

    print("Creating mixed preview audio...")
    mixed_preview_audio = create_mixed_preview(
        mic_audio=paths.mic_audio,
        system_audio=paths.system_audio,
        output_audio=paths.mixed_preview_audio,
    )

    mic_transcript_txt = None
    system_transcript_txt = None

    if mic_whisper_audio:
        print("Transcribing microphone audio...")
        mic_transcript_txt = transcribe(
            audio_path=mic_whisper_audio,
            output_dir=paths.session_dir,
            output_name="mic_transcript",
            language=language,
            model=model,
        )
    else:
        print("Skipping microphone transcription: no mic audio found.")

    if system_whisper_audio:
        print("Transcribing system audio...")
        system_transcript_txt = transcribe(
            audio_path=system_whisper_audio,
            output_dir=paths.session_dir,
            output_name="system_transcript",
            language=language,
            model=model,
        )
    else:
        print("Skipping system transcription: no system audio found.")

    return PipelineResult(
        session_dir=paths.session_dir,
        mic_whisper_audio=mic_whisper_audio,
        system_whisper_audio=system_whisper_audio,
        mixed_preview_audio=mixed_preview_audio,
        mic_transcript_txt=mic_transcript_txt,
        system_transcript_txt=system_transcript_txt,
    )
