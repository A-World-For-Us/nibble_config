defmodule NibbleConfig do
  @moduledoc """
  NibbleConfig lets each module declare and load its own configuration,
  instead of scattering configuration across `config/*.exs` files.

  ## Usage

  Modules requiring configuration can implement the `NibbleConfig` behaviour,
  and declare and use their own configuration:

      defmodule MyApp.MyExternalService do
        use NibbleConfig, otp_app: :my_app

        @impl NibbleConfig
        def load_config(_ctx) do
          [
            api_key: System.fetch_env!("API_KEY"),
            # `Config.config_env/0` and `Config.config_target/0` are automatically
            # imported so you can refine the configuration based on the env and target.
            timeout: if(config_env() == :prod, do: 5_000, else: 60_000)
          ]
        end

        def call_service(path) do
          # Read the configuration
          api_key = config(:api_key)
          timeout = config(:timeout)

          HttpClient.get(path, api_key, timeout)
        end
      end

  They then need to be declared in `config/runtime.exs`:

      NibbleConfig.new()
      |> NibbleConfig.load_for(:my_app, MyApp.MyExternalService)
      |> NibbleConfig.load_for(:my_app, MyApp.SomeOtherService)
      |> NibbleConfig.apply_config()

  """

  @enforce_keys [:loaded_configs]
  defstruct [:loaded_configs]

  @type t :: %__MODULE__{
          loaded_configs: loaded_configs()
        }

  @typep loaded_configs :: %{
           optional(otp_app :: atom()) => [{module(), module_config :: %{term() => term()}}]
         }

  @doc """
  Initialize a new, empty configuration loader.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      loaded_configs: %{}
    }
  end

  @doc """
  Loads `module`'s configuration and stores it. The configuration is converted
  to a map before being stored.

  `module` must implement the `NibbleConfig` behaviour.
  """
  @spec load_for(t(), atom(), module()) :: t()
  def load_for(%__MODULE__{} = nibble_config, otp_app, module) when is_atom(otp_app) and is_atom(module) do
    if not Code.ensure_loaded?(module) do
      raise ArgumentError, "module #{inspect(module)} is not loaded"
    end

    module_config =
      nibble_config
      |> module.load_config()
      |> Map.new()

    updated_loaded_configs =
      Map.update(
        nibble_config.loaded_configs,
        otp_app,
        [{module, module_config}],
        fn existing_configs -> [{module, module_config} | existing_configs] end
      )

    %{nibble_config | loaded_configs: updated_loaded_configs}
  end

  @doc """
  Writes all loaded configuration to the application environment.
  """
  @spec apply_config(t()) :: :ok
  def apply_config(%__MODULE__{} = nibble_config) do
    for {otp_app, configuration} <- nibble_config.loaded_configs do
      Config.config(otp_app, configuration)
    end

    :ok
  end

  @doc """
  Returns this module's configuration, as a map or `{key, value}` pairs.

  You can call `config_env/0` and `config_target/0` from this callback to refine
  the returned configuration based on the current environment.
  """
  @callback load_config(t()) :: Enumerable.t({key :: term(), value :: term()})

  @doc """
  Declares the calling module as configuration for `:otp_app`.

  ## Options

  - `:otp_app` (recommended) - the OTP app to get configuration from.
    Setting it defines a private `config/1` function to fetch a single key of the module
    configuration from within itself, and a public `loaded_configuration/0` returning
    the whole configuration map.

  """
  defmacro __using__(opts) do
    otp_app = Keyword.get(opts, :otp_app)

    quote do
      @behaviour unquote(__MODULE__)

      import Config, only: [config_env: 0, config_target: 0]

      if unquote(otp_app != nil) do
        @spec config(key :: term()) :: value :: term()
        defp config(key) do
          Map.fetch!(loaded_configuration(), key)
        end

        @doc """
        Get the configuration map used by this module.
        """
        @spec loaded_configuration() :: map()
        def loaded_configuration do
          Application.fetch_env!(unquote(otp_app), __MODULE__)
        end
      end
    end
  end
end
