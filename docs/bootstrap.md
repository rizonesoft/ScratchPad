# Bootstrap

From zero to a green build and test run. Script-first: the provisioner installs the toolchain and this doc explains each step. Follow it top to bottom with no improvisation; `docs/build.md` is the command reference once you are set up.

## Prerequisites

| Need | Version | Notes |
| ---- | ------- | ----- |
| git | any 2.x | clone plus the commit stamp `SourceLink` reads |
| Linux: python3, curl, tar, sha512sum | inbox on Ubuntu 24.04 | the provisioner checks and names anything missing |
| Windows: PowerShell 5.1 or later | inbox | run the provisioner with `-ExecutionPolicy Bypass` |
| .NET SDK 10.0.401 | exact, from `global.json` | installed repo-local by the provisioner; never install it by hand |
| WindowsAppRuntime 2.x | launch only | needed to RUN the stub, not to build or test; check with `Get-AppxPackage -Name '*WindowsAppRuntime*'` |

Install order: git first (if missing), then clone, then provision (which installs the SDK), then build, then test. Nothing else is installed at any point.

## Steps

1. `git clone https://github.com/rizonesoft/intelligent-notepad.git` and `cd intelligent-notepad`.
2. Provision the SDK. Linux: `./tools/provision.sh`. Windows: `powershell -ExecutionPolicy Bypass -File tools\provision.ps1`. Expect it to end with `ready in .../.tools/dotnet-<rid>` after printing `dotnet --info` for SDK 10.0.401.
3. Put the repo-local SDK on the path. Linux: `export DOTNET_ROOT="$PWD/.tools/dotnet-linux-x64" PATH="$PWD/.tools/dotnet-linux-x64:$PATH" DOTNET_MULTILEVEL_LOOKUP=0`. Windows: `$env:DOTNET_ROOT = "$PWD\.tools\dotnet-win-x64"; $env:PATH = "$PWD\.tools\dotnet-win-x64;" + $env:PATH; $env:DOTNET_MULTILEVEL_LOOKUP = "0"`. Every SDK command below needs these set; step output that says otherwise means you skipped this step (see failure 1).
4. Build. Linux: `dotnet build src/Notepad.Neutral.slnf`. Windows: `dotnet build src/IntelligentNotepad.slnx`. Expect `Build succeeded` with `0 Warning(s)`.
5. Test. Linux: `dotnet test src/Notepad.Neutral.slnf`. Windows: `dotnet test src/IntelligentNotepad.slnx`. Expect `Passed!` with 1/1.
6. (Windows only) Run the stub: `src\IntelligentNotepad\bin\Debug\net10.0-windows10.0.19041.0\win-x64\IntelligentNotepad.exe`. Expect a window whose title carries the stub version and runtime.

## OS boundary

| Command | Linux | Windows |
| ------- | :---: | :-----: |
| `dotnet build src/Notepad.Neutral.slnf` | yes | yes |
| `dotnet test src/Notepad.Neutral.slnf` | yes | yes |
| `dotnet build src/IntelligentNotepad.slnx` | no (XAML compiler is Windows-only) | yes |
| `dotnet test src/IntelligentNotepad.slnx` | no (contains the app) | yes |
| Run the stub | no | yes (needs WindowsAppRuntime 2.x) |
| UI suites, captures, packaging | no | yes (land with D00 T02, D07) |

A Linux reader runs the first two rows and stops; everything below them is Windows work.

## Troubleshooting

Failure 1: `dotnet build` says `The command could not be loaded ... A compatible .NET SDK was not found.` You skipped step 3: the shell resolved a machine SDK (or none) and `global.json` refuses anything but 10.0.401, even one patch off. Fix: run the step 3 export for your OS and retry; verify with `dotnet --info`, which must show the SDK under your checkout's `.tools/`. Never fix this by installing an SDK by hand.

Failure 2: from WSL, `powershell.exe` fails with `WSL UtilBindVsockAnyPort: socket failed 1` and the Windows provisioner cannot run. The WSL interop channel is down in that session (observed under sandboxed agent sessions; direct runs from Windows PowerShell are unaffected). Fix: run `tools\provision.ps1` from Windows PowerShell directly instead of through interop.
