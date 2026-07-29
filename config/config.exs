import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    # Instructs the tool to manage the mix version in `mix.exs`
    manage_mix_version?: true,
    # Instructs the tool to update the version in the README.md
    manage_readme_version: true
end
