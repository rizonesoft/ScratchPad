# Build

One command per OS, no IDE required. CI runs the same commands (§3).

## CI workflows

Two workflows run on pushes to `main`: `build` compiles and tests on Linux and Windows, while `plan-gates` runs the TODO graph self-test, tree validation, and plan-projection check only when the push touches `scripts/`, `todo/`, or the workflow itself, so documentation-only edits skip the graph checks (§7).

## Prerequisites

Provision the pinned SDK first: `./tools/provision.sh` on Linux, `powershell -ExecutionPolicy Bypass -File tools\provision.ps1` on Windows. Then put it on the path: `export DOTNET_ROOT="$PWD/.tools/dotnet-linux-x64" PATH="$PWD/.tools/dotnet-linux-x64:$PATH" DOTNET_MULTILEVEL_LOOKUP=0` (Windows: `.tools\dotnet-win-x64`). Launching the stub additionally needs the WindowsAppRuntime 2.x framework package on the machine; check with `Get-AppxPackage -Name '*WindowsAppRuntime*'` and install it from `https://aka.ms/windowsappsdk/2.4/2.4.0/windowsappruntimeinstall-x64.exe` (matching SDK 2.4.0) if it is missing. CI installs it via the `Install WindowsAppRuntime` step.

## Build commands

Linux builds the neutral scope (the WinUI XAML compiler is Windows-only, so the app project is excluded by filter): `dotnet build src/Notepad.Neutral.slnf`. Windows builds everything: `dotnet build src/IntelligentNotepad.slnx`. Both exit 0 on a clean tree and leave `git status` clean: outputs land under per-project `bin/` and `obj/`, publish output under `dist/`, all gitignored.

## Test

Linux runs the neutral scope including smoke: `dotnet test src/Notepad.Neutral.slnf`. Windows runs the same tests through the full solution: `dotnet test src/IntelligentNotepad.slnx`. Run only the smoke test with `dotnet test <solution> --filter Smoke`. Test output uses the default console logger; anything written under `TestResults/` is gitignored.

## Warnings and analysis

Warnings fail the build everywhere: `Directory.Build.props` sets `TreatWarningsAsErrors`, `EnforceCodeStyleInBuild`, and `AnalysisLevel latest` with `AnalysisMode All`, and `.editorconfig` carries the ruleset (generated code excluded by path). The CI jobs run the same `dotnet build` commands above, so analysis runs identically locally and in CI; reproduce a CI finding by running the matching build command.

## Run the stub (Windows)

Build the solution, then run `src\IntelligentNotepad\bin\Debug\net10.0-windows10.0.19041.0\win-x64\IntelligentNotepad.exe` directly. The window title carries the stub version and runtime (for example `Intelligent Notepad (stub 0.0.0+<sha>, .NET 10.0.12)`).

## Provenance

The app stamps the git commit into the binary via `SourceRevisionId`, so the provenance of a binary is answerable from the binary: `([System.Diagnostics.FileVersionInfo]::GetVersionInfo('IntelligentNotepad.exe')).ProductVersion` prints `0.0.0+<sha>`. Package versions are locked by `src/IntelligentNotepad/packages.lock.json`; the stub itself is version 0.0.0 and real release versions arrive with D07.
