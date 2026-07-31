defmodule NibbleConfigTest do
  use ExUnit.Case

  doctest NibbleConfig

  defmodule ModuleWithApp do
    @moduledoc false
    use NibbleConfig, otp_app: :nibble_config_test_app

    @impl NibbleConfig
    def load_config(_ctx), do: [foo: 1, bar: "baz"]

    def get(key), do: config(key)
  end

  defmodule ModuleWithoutApp do
    @moduledoc false
    use NibbleConfig

    @impl NibbleConfig
    def load_config(_ctx), do: [foo: 1]
  end

  defmodule ModuleUsingConfigEnv do
    @moduledoc false
    use NibbleConfig, otp_app: :nibble_config_test_app

    @impl NibbleConfig
    def load_config(_ctx), do: [env: config_env(), target: config_target()]
  end

  defmodule ModuleReturningMap do
    @moduledoc false
    use NibbleConfig, otp_app: :nibble_config_test_app

    def load_config(_ctx), do: %{a: 1, b: 2}
  end

  defmodule ModuleCapturingCtx do
    @moduledoc false
    use NibbleConfig, otp_app: :nibble_config_test_app

    def load_config(ctx) do
      send(self(), {:ctx, ctx})
      [a: 1]
    end
  end

  describe "new/0" do
    test "returns an empty loader" do
      assert NibbleConfig.new() == %NibbleConfig{loaded_configs: %{}}
    end
  end

  describe "load_for/3" do
    test "loads a module's config, converts it to a map, and stores it under the given otp_app" do
      nc = NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithApp, otp_app: :other_app)

      assert nc.loaded_configs == %{
               other_app: [{NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}]
             }
    end

    test "infers the otp_app from `use NibbleConfig, otp_app: ...`" do
      nc = NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithApp)

      assert nc.loaded_configs == %{
               nibble_config_test_app: [{NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}]
             }
    end

    test "the :otp_app option takes precedence over the one declared with `use NibbleConfig`" do
      nc = NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithApp, otp_app: :override_app)

      assert Map.keys(nc.loaded_configs) == [:override_app]
    end

    test "accepts a load_config/1 callback returning a map" do
      nc = NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleReturningMap)

      assert nc.loaded_configs == %{nibble_config_test_app: [{NibbleConfigTest.ModuleReturningMap, %{a: 1, b: 2}}]}
    end

    test "passes the pre-update accumulator as ctx to load_config/1" do
      nc = NibbleConfig.new()

      NibbleConfig.load_for(nc, NibbleConfigTest.ModuleCapturingCtx)

      assert_received {:ctx, ^nc}
    end

    test "prepends new entries for the same otp_app, most-recently-loaded first" do
      nc =
        NibbleConfig.new()
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleReturningMap)

      assert nc.loaded_configs[:nibble_config_test_app] == [
               {NibbleConfigTest.ModuleReturningMap, %{a: 1, b: 2}},
               {NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}
             ]
    end

    test "keeps configs for different otp_apps independent" do
      nc =
        NibbleConfig.new()
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp, otp_app: :app_a)
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleReturningMap, otp_app: :app_b)

      assert nc.loaded_configs == %{
               app_a: [{NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}],
               app_b: [{NibbleConfigTest.ModuleReturningMap, %{a: 1, b: 2}}]
             }
    end

    test "raises ArgumentError when the module isn't loaded" do
      assert_raise ArgumentError, fn ->
        NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.DoesNotExist)
      end
    end

    test "raises ArgumentError when no :otp_app is given and the module wasn't declared with one" do
      assert_raise ArgumentError,
                   "no :otp_app given and NibbleConfigTest.ModuleWithoutApp was not declared with `use NibbleConfig, otp_app: ...`",
                   fn ->
                     NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithoutApp)
                   end
    end

    test "raises FunctionClauseError when module isn't an atom" do
      assert_raise FunctionClauseError, fn ->
        apply(NibbleConfig, :load_for, [NibbleConfig.new(), "not_an_atom"])
      end
    end

    test "raises UndefinedFunctionError when the module doesn't implement load_config/1" do
      assert_raise UndefinedFunctionError, fn ->
        NibbleConfig.load_for(NibbleConfig.new(), String)
      end
    end

    test "calling load_for twice for the same module produces two separate entries (no dedup)" do
      nc =
        NibbleConfig.new()
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
        |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)

      assert nc.loaded_configs[:nibble_config_test_app] == [
               {NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}},
               {NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}
             ]
    end
  end

  describe "finalize/1" do
    defp eval_config(code) do
      Config.Reader.eval!("nofile.exs", code, env: :test, target: :host)
    end

    test "is a no-op returning :ok for an empty loader" do
      assert NibbleConfig.finalize(NibbleConfig.new()) == :ok
    end

    test "writes a module's config to the application env when run through Config.Reader" do
      code = """
      NibbleConfig.new()
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
      |> NibbleConfig.finalize()
      """

      assert eval_config(code) == [
               nibble_config_test_app: [
                 {NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}
               ]
             ]
    end

    test "writes config for multiple modules under the same otp_app" do
      code = """
      NibbleConfig.new()
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleReturningMap, otp_app: :nibble_config_test_app)
      |> NibbleConfig.finalize()
      """

      assert eval_config(code) == [
               {:nibble_config_test_app,
                [
                  {NibbleConfigTest.ModuleReturningMap, %{a: 1, b: 2}},
                  {NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}
                ]}
             ]
    end

    test "writes config for multiple otp_apps independently" do
      code = """
      NibbleConfig.new()
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp, otp_app: :nibble_config_test_app_a)
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleReturningMap, otp_app: :nibble_config_test_app_b)
      |> NibbleConfig.finalize()
      """

      assert eval_config(code) == [
               {:nibble_config_test_app_a, [{NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"}}]},
               {:nibble_config_test_app_b, [{NibbleConfigTest.ModuleReturningMap, %{a: 1, b: 2}}]}
             ]
    end

    test "loading the same module twice under the same otp_app raises when the config is actually applied" do
      code = """
      NibbleConfig.new()
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleWithApp)
      |> NibbleConfig.finalize()
      """

      result = eval_config(code)

      assert_raise ArgumentError, fn -> Application.put_all_env(result) end
    end

    test "load_config/1 can call config_env/0 and config_target/0 when run through Config.Reader" do
      code = """
      NibbleConfig.new()
      |> NibbleConfig.load_for(NibbleConfigTest.ModuleUsingConfigEnv)
      |> NibbleConfig.finalize()
      """

      assert eval_config(code) == [
               {:nibble_config_test_app, [{NibbleConfigTest.ModuleUsingConfigEnv, %{env: :test, target: :host}}]}
             ]
    end
  end

  describe "use NibbleConfig, otp_app: ..." do
    test "applies the NibbleConfig behaviour" do
      attributes = NibbleConfigTest.ModuleWithApp.module_info(:attributes)
      assert NibbleConfig in Keyword.fetch!(attributes, :behaviour)
    end

    test "loaded_configuration/0 returns the application env set for the module" do
      Application.put_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"})
      on_exit(fn -> Application.delete_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp) end)

      assert NibbleConfigTest.ModuleWithApp.loaded_configuration() == %{foo: 1, bar: "baz"}
    end

    test "loaded_configuration/0 raises when the app/module was never configured" do
      Application.delete_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp)

      assert_raise ArgumentError, fn ->
        NibbleConfigTest.ModuleWithApp.loaded_configuration()
      end
    end

    test "the private config/1 fetches a key from loaded_configuration/0" do
      Application.put_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"})
      on_exit(fn -> Application.delete_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp) end)

      assert NibbleConfigTest.ModuleWithApp.get(:foo) == 1
      assert NibbleConfigTest.ModuleWithApp.get(:bar) == "baz"
    end

    test "the private config/1 raises KeyError for a missing key" do
      Application.put_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp, %{foo: 1, bar: "baz"})
      on_exit(fn -> Application.delete_env(:nibble_config_test_app, NibbleConfigTest.ModuleWithApp) end)

      assert_raise KeyError, fn ->
        NibbleConfigTest.ModuleWithApp.get(:missing)
      end
    end
  end

  describe "use NibbleConfig (without otp_app)" do
    test "still applies the NibbleConfig behaviour" do
      attributes = NibbleConfigTest.ModuleWithoutApp.module_info(:attributes)
      assert NibbleConfig in Keyword.get(attributes, :behaviour, [])
    end

    test "does not define loaded_configuration/0" do
      refute function_exported?(NibbleConfigTest.ModuleWithoutApp, :loaded_configuration, 0)
    end

    test "does not define a public config/1" do
      refute function_exported?(NibbleConfigTest.ModuleWithoutApp, :config, 1)
    end

    test "the module still works with load_for/3 when given an explicit :otp_app" do
      nc = NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithoutApp, otp_app: :test_app)

      assert nc.loaded_configs == %{test_app: [{NibbleConfigTest.ModuleWithoutApp, %{foo: 1}}]}
    end

    test "raises ArgumentError when loaded via load_for/3 without an :otp_app" do
      assert_raise ArgumentError, fn ->
        NibbleConfig.load_for(NibbleConfig.new(), NibbleConfigTest.ModuleWithoutApp)
      end
    end
  end
end
