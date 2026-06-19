import Config

config :watson,
  recordings_dir: Path.expand("recordings", __DIR__ <> "/.."),
  helper_path: Path.expand("native/macos_recorder/.build/release/watson-recorder", __DIR__ <> "/.."),
  mlx_whisper_path: "mlx_whisper",
  transcription_cadence_ms: 15_000,
  transcription_overlap_ms: 1_500,
  language: "ru",
  model: "mlx-community/whisper-large-v3-turbo",
  capture_helper: Watson.Capture.Helper
