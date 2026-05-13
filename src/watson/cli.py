from pathlib import Path

import typer

from watson.pipeline import record_and_transcribe

app = typer.Typer(no_args_is_help=True)


@app.command()
def record(
    language: str = typer.Option("ru", "--language", "-l"),
    model: str = typer.Option(
        "mlx-community/whisper-large-v3-turbo",
        "--model",
        "-m",
    ),
    output_dir: Path = typer.Option(Path("recordings"), "--output-dir", "-o"),
) -> None:
    """
    Record microphone + system audio, then transcribe both tracks separately.
    Stop recording with Ctrl+C.
    """
    result = record_and_transcribe(
        language=language,
        model=model,
        output_dir=output_dir,
    )

    typer.echo("")
    typer.echo("Done.")
    typer.echo(f"Session: {result.session_dir}")

    if result.mic_transcript_txt:
        typer.echo(f"Mic transcript:    {result.mic_transcript_txt}")

    if result.system_transcript_txt:
        typer.echo(f"System transcript: {result.system_transcript_txt}")

    if result.mixed_preview_audio:
        typer.echo(f"Mixed preview:     {result.mixed_preview_audio}")
