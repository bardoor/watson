import Config

env_overrides = [
  {"WATSON_RECORDINGS_DIR", :recordings_dir},
  {"WATSON_HELPER_PATH", :helper_path},
  {"WATSON_MLX_WHISPER_PATH", :mlx_whisper_path},
  {"WATSON_LANGUAGE", :language},
  {"WATSON_MODEL", :model}
]

Enum.each(env_overrides, fn {env_name, key} ->
  case System.get_env(env_name) do
    nil -> :ok
    value -> config :watson, key, value
  end
end)
