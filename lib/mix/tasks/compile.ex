defmodule Mix.Tasks.Tz.Compile do
  use Mix.Task

  alias Tz.Compiler

  @shortdoc "Compiles the time zone periods for given IANA version."
  def run([]) do
    Mix.shell().info("Tz is recompiling time zone periods...")

    Code.compiler_options(ignore_module_conflict: true)
    Compiler.compile()
    Code.compiler_options(ignore_module_conflict: false)

    Mix.shell().info("Tz compilation done with IANA version #{Tz.iana_version()}")
  end

  def run(_) do
    Mix.raise "command doesn't accept any arguments"
  end
end
