import Config

config :watson,
  capture_helper: Watson.TestCaptureHelper,
  mlx_whisper_path: Path.expand("../test/support/mlx_whisper_stub", __DIR__),
  transcription_cadence_ms: 60_000
