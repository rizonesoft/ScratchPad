# Bootstrap

From zero to a green build and test run. Script-first: the provisioner installs the toolchain and this doc explains each step. Follow it top to bottom with no improvisation; `docs/build.md` is the command reference once you are set up.

## Prerequisites

| Need | Version | Notes |
| ---- | ------- | ----- |
| git | any 2.x | clone plus the commit stamp `SourceLink` reads |
| Windows: PowerShell 5.1 or later | inbox | run the provisioner with `-ExecutionPolicy Bypass` |
| Windows: Python 3 | 3.x, `py --version` works | for the pre-commit TODO gate; install from python.org or `winget install Python.Python.3` |
| .NET SDK 10.0.400 | exact, from `global.json` | installed repo-local by the provisioner; never install it by hand |
| WindowsAppRuntime 2.x | launch only | needed to RUN the stub, not to build or test; check with `Get-AppxPackage -Name '*WindowsAppRuntime*'` |

Install order: git first (if missing), then clone, then provision (which installs the SDK), then build, then test. Nothing else is installed at any point.

## Steps

1. `git clone https://github.com/rizonesoft/ScratchPad.git` and `cd ScratchPad`.
2. Provision the SDK: `powershell -ExecutionPolicy Bypass -File tools\provision.ps1`. Expect it to end with `ready in .../.tools/dotnet-win-x64` after printing `dotnet --info` for SDK 10.0.400.
3. Put the repo-local SDK on the path: `$env:DOTNET_ROOT = "$PWD\.tools\dotnet-win-x64"; $env:PATH = "$PWD\.tools\dotnet-win-x64;" + $env:PATH; $env:DOTNET_MULTILEVEL_LOOKUP = "0"`. Every SDK command below needs these set; step output that says otherwise means you skipped this step (see failure 1).
4. Build: `dotnet build src/ScratchPad.slnx`. Expect `Build succeeded` with `0 Warning(s)`.
5. Test: `dotnet test src/ScratchPad.slnx`. Expect `Passed!` with 1/1.
6. Run the stub: `py tools/launch.py`. It resolves `Bin\ScratchPad\Debug\win-x64\ScratchPad.exe` and launches it. Expect a window whose title carries the stub version and runtime.

## Git hooks (one-time for existing clones)

New clones get the commit gate from the provisioner. If the provisioner never printed `git hooks wired to tools/githooks`, wire it by hand once: `git config core.hooksPath tools/githooks`, then verify with `git config --get core.hooksPath` (expect `tools/githooks`).

The hook validates the staged tree with `scripts/todo-graph.py validate` on every commit and refuses the commit when it is red (a FATAL, or a warning no baseline entry covers). It needs Python 3 on PATH (see Prerequisites).

## Build scopes

`src/ScratchPad.slnx` builds and tests everything. `src/Notepad.Neutral.slnf` filters the neutral libraries for a fast check without the app: `dotnet build src/Notepad.Neutral.slnf`. The full solution, app launch, UI suites, captures, and packaging run on Windows only.

## Troubleshooting

Failure 1: `dotnet build` says `The command could not be loaded ... A compatible .NET SDK was not found.` You skipped step 3: the shell resolved a machine SDK (or none) and `global.json` refuses anything but 10.0.400, even one patch off. Fix: run the step 3 export for your OS and retry; verify with `dotnet --info`, which must show the SDK under your checkout's `.tools/`. Never fix this by installing an SDK by hand.

Failure 2: `powershell -ExecutionPolicy Bypass -File tools\provision.ps1` fails with `WSL UtilBindVsockAnyPort: socket failed 1`. You ran the Windows provisioner from inside WSL and the interop channel is down in that session. Fix: run it from Windows PowerShell directly instead of through interop.
