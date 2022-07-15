Benchee.run(
  %{
    "compiler" => fn ->
      Code.compiler_options(ignore_module_conflict: true)
      Tz.Compiler.compile()
      Code.compiler_options(ignore_module_conflict: false)
    end,
  },
  memory_time: 10
)
