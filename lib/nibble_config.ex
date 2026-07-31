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
      |> NibbleConfig.load_for(MyApp.MyExternalService)
      |> NibbleConfig.load_for(MyApp.SomeOtherService)
      |> NibbleConfig.finalize()

  """

  @enforce_keys [:internal]
  defstruct [:internal]

  @typedoc """
  The context passed around the configuration.

  ## Fields

  - `:internal` - used for data internal to the library only, do not use it.
  """
  @type t :: %__MODULE__{
          internal: internal()
        }

  @typep internal :: %{
           loaded_configs: %{
             optional(otp_app :: atom()) => [{module(), module_config :: %{term() => term()}}]
           }
         }

  @doc """
  Initialize a new, empty configuration loader.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      internal: %{
        loaded_configs: %{}
      }
    }
  end

  @typedoc """
  - `:otp_app` - the OTP app to store `module`'s configuration under. Only required
    if `module` was not declared with `use NibbleConfig, otp_app: ...`; when given,
    it takes precedence over the value declared by `use NibbleConfig`.
  """
  @type load_for_opt :: {:otp_app, atom()}

  @doc """
  Loads `module`'s configuration and stores it. The configuration is converted
  to a map before being stored.

  `module` must implement the `NibbleConfig` behaviour.
  """
  @spec load_for(t(), module(), [load_for_opt()]) :: t()
  def load_for(%__MODULE__{} = nibble_config, module, opts \\ []) when is_atom(module) do
    if not Code.ensure_loaded?(module) do
      raise ArgumentError, "module #{inspect(module)} is not loaded"
    end

    otp_app =
      cond do
        option_otp_app = Keyword.get(opts, :otp_app) ->
          option_otp_app

        inferred_otp_app = module.__nimble_otp_app__() ->
          inferred_otp_app

        true ->
          raise ArgumentError,
                "no :otp_app given and #{inspect(module)} was not declared with `use NibbleConfig, otp_app: ...`"
      end

    module_config =
      nibble_config
      |> module.load_config()
      |> Map.new()

    update_in(nibble_config.internal.loaded_configs[otp_app], fn
      existing_configs when is_list(existing_configs) -> [{module, module_config} | existing_configs]
      nil -> [{module, module_config}]
    end)
  end

  @doc """
  Apply the configuration, and terminates the instance.
  """
  @spec finalize(t()) :: :ok
  def finalize(%__MODULE__{} = nibble_config) do
    for {otp_app, configuration} <- nibble_config.internal.loaded_configs do
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

      @doc false
      def __nimble_otp_app__, do: unquote(otp_app)

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
