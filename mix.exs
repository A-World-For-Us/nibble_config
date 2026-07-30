defmodule NibbleConfig.MixProject do
  use Mix.Project

  @version "0.2.0"
  @url "https://github.com/A-World-For-Us/nibble_config"

  def project do
    [
      app: :nibble_config,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      docs: docs(),

      # Hex
      description: "Co-localize configuration with usage",
      package: package(),

      # Dialyzer
      dialyzer: [
        # Put the project-level PLT in the priv/ directory (instead of the default _build/ location)
        # for the CI to be able to cache it between builds
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :test
      ]
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "deps.compile",
        "git_ops.message_hook"
      ],
      release: ["git_ops.release --yes"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:dialyxir, "~> 1.4", only: :test, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:git_ops, "~> 2.10", only: :dev, runtime: false},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "NibbleConfig",
      extras: ["CHANGELOG.md"],
      source_ref: @version,
      source_url: @url
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @url,
        "Changelog" => "#{@url}/blob/#{@version}/CHANGELOG.md"
      }
    ]
  end
end
