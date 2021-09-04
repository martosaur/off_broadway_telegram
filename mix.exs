defmodule OffBroadway.Telegram.MixProject do
  use Mix.Project

  @version "0.1.0"
  @description "Off-Broadway producer for Telegram Bot API"

  def project do
    [
      app: :off_broadway_telegram,
      version: @version,
      elixir: "~> 1.11",
      name: "OffBroadwayTelegram",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: @description,
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:broadway, "~> 1.0.0"},
      {:nadia, "~> 0.7.0"},
      {:ex_doc, "~> 0.25.2", only: :docs}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/martosaur/off_broadway_telegram",
      extras: ["README.md"]
    ]
  end

  defp package do
    %{
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/martosaur/off_broadway_telegram"}
    }
  end
end
