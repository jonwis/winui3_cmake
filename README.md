# winui3_cmake
CMake scripts for building WinUI 3 apps.

Useful if you want to build a a WinUI 3 app with CMake and not necessarily use the Visual Studio generator.

Provides the following functionality:
* Run `nuget install`, get package directories
* Locate Windows 10 SDK & relevant files within
* Generate `.winmd` files using `midl`
* Merge `.winmd` files using `mdmerge`
* Generate headers using `cppwinrt`
* Create `.pri` files
* Compile `.xaml` files using standalone `XamlCompiler.exe`

# Embedding the generators

The `cmake` directory can be exposed with FetchContent's `SOURCE_SUBDIR cmake`,
then individual modules included by absolute path. It intentionally has no
`CMakeLists.txt`: this does not run the repository's root project, restore NuGet
packages, or build samples. Existing package restoration and consuming projections
can remain owned by the embedding project.

Explicit `TOOL` executable paths bypass package/tool discovery. For IDL generation,
also supply `METADATA_DIR`, or use `NO_DEFAULT_ARGS`, to avoid SDK metadata discovery.
Without these overrides the original package-discovered tools remain the defaults.
The executable itself is a build dependency.

| Helper | Optional explicit controls |
| --- | --- |
| `winmd_from_idl` | `TOOL`, `METADATA_DIR`, `INCLUDE_DIRS`, `ARGS`, `DEPENDS`, `OUTPUTS`, `BYPRODUCTS`, `WORKING_DIRECTORY`, `NO_DEFAULT_ARGS` |
| `merge_winmds` | `TOOL`, `OUTPUTS`, `DEPTH`, `METADATA_DIRS`, `NO_PARTIAL`, `EXPLICIT_DEPENDENCIES`, `ARGS`, `DEPENDS`, `WORKING_DIRECTORY` |
| `run_cppwinrt` | `TOOL`, `OUTPUTS`, `BYPRODUCTS`, `DEPENDS`, `ARGS`, `WORKING_DIRECTORY`, `BARE_COMPONENT` |
| `make_pri`, `make_pri_postbuild` | `TOOL`, `CONFIG_XML`, `PROJECT_ROOT`, `INDEX_NAME`, `DEPENDS`, `ARGS`, `EMPTY`, `RESOURCE_INPUTS` |

`ARGS` is an ordered argv list, not a shell command or a response-file string.
`DEPENDS` accepts ordinary CMake file/target dependencies, including generated
references and explicitly listed IDL imports. Input/reference paths are interpreted
relative to `WORKING_DIRECTORY` (default: the calling source directory); output
roots are relative to the calling binary directory. Declare every consumed output
in `OUTPUTS` and incidental generated files in `BYPRODUCTS` so Ninja can recover
when they are deleted. Reference-directory WinMDs are tracked recursively, without
examining their namespaces, except when `merge_winmds(EXPLICIT_DEPENDENCIES)` is
selected as described below. Directory-valued `IN`/`REF` must exist at configure
time; generated contents additionally need explicit producer/file `DEPENDS`.
An absent `IN`/`REF` path is treated as a file dependency, not inferred to be a
future directory. Separate `METADATA_DIR`/`METADATA_DIRS` may be supplied before
their contents exist, with explicit producer/file `DEPENDS` for those contents.

## WinRT metadata

`winmd_from_idl` retains `IN`, `OUT`, `REF` and optional `WINSDK_VERSION`.
Its default flags are `/nologo /winrt /nomidl /h nul`. `NO_DEFAULT_ARGS` replaces
that flag set with the caller's `ARGS`; the structured `/winmd`, `/metadata_dir`,
`/I`, `/reference`, and IDL input arguments are still emitted. Include `/winrt`
directly in `ARGS` when selecting the WinRT MIDL driver. This is not a COM proxy
generator.

`merge_winmds` still defaults to `-partial -n:1`. `DEPTH DEFAULT` omits `-n`;
`NO_PARTIAL` omits `-partial`. An explicit `OUTPUTS` list replaces the single
`OUTDIR/NAMESPACE.winmd` contract. `METADATA_DIRS` replaces directories derived
from `REF`, retaining unique directories in first-seen order after path
normalization. Extra arguments are appended after these standard options.

`EXPLICIT_DEPENDENCIES` disables all metadata-directory scanning, including
directories derived from `REF`. Search paths still reach mdmerge through
`-metadata_dir`; metadata file dependencies come only from `IN`, `REF`, and `DEPENDS`.
List the complete consumed reference set as files in `REF` or `DEPENDS`,
including generated WinMDs and transitive references resolved through search
directories. Generated files need declared producing commands; a target-only
`DEPENDS` orders generation but does not track changes to its files. Directory
membership changes then require updating the explicit list. This mode avoids
CMake regeneration when generated metadata directories are populated or cleaned.
Without the option, recursive discovery and membership tracking remain unchanged
for callers relying on directory-only dependencies.

After successful merges, an output inventory removes only previously declared,
now-obsolete files contained within the output root. Unlisted files and files
outside that root are not pruned. `cmake/prune_outputs.cmake` is also usable with
`cmake -DROOT=... -DOWNED=... -DINVENTORY=... -P ...`: `INVENTORY` contains absolute
output paths, one per line; `OWNED` records the last successful inventory.

## C++/WinRT

`COMPONENT` emits `-comp <directory>`; `BARE_COMPONENT` emits `-comp` without a
directory. PCH is omitted unless supplied. Existing overwrite/optimize/prefix/name
options are unchanged. Component mode always declares `module.g.cpp`, in addition
to the caller's outputs/byproducts. The stamp is touched only after successful
generation and is not an always-run step. `GENERATED_SOURCES` retains its original
module-source result; additional outputs need not be compilable sources.

## PRI

The original `DIRECTORY`/`FILES` mode retains RESFILES and EMBEDFILES indexing.
`EMPTY` generates a RESFILES-only configuration with index root `\`, normally
with no `FILES`. `RESOURCE_INPUTS` uses the same root and enables RESW, RESJSON,
PRI and RESFILES indexing. Optional boolean `RESW`, `RESJSON`, `PRI`, `RESFILES`
select a subset instead. RESW enables dotted-name conversion; RESW/RESJSON use
`INDEX_NAME` as their initial path. `FILES` contains resource entries relative to
`DIRECTORY`, or absolute paths; generated empty/resource manifests use native path
spelling.

`CONFIG_XML` bypasses generated XML and does not require `DIRECTORY`. Its file
and any `DEPENDS` are tracked. `PROJECT_ROOT` defaults to the caller's source
directory; `INDEX_NAME` optionally adds `-IndexName`. Extra `ARGS` follow the
standard New/ProjectRoot/ConfigXml/OutputFile/Overwrite options. The PowerShell
wrapper receives the executable and argv separately and propagates native errors.
Prefer output-based `make_pri` for Ninja scheduling: the original post-build form
still depends on a target actually being rebuilt.

## Isolated scheduling checks

On Windows, run:

```powershell
.\tests\generators\run.ps1 -CMake <cmake.exe> -Ninja <ninja.exe>
.\tests\generators\run_metadata_dependencies.ps1 -CMake <cmake.exe> -Ninja <ninja.exe>
```

The compiler-free CMake project uses synthetic metadata/resources and a fake
console executable generated by Windows PowerShell's built-in `Add-Type`.
No NuGet restoration, SDK/Visual Studio discovery or real Windows generator tools
are needed. Checks exercise actual Ninja edges, argv with spaces, incremental
dependencies, missing outputs, merge pruning, PRI profiles and failure propagation.

# Caveats

The standalone `XamlCompiler.exe` has broken error reporting (see https://github.com/microsoft/microsoft-ui-xaml/issues/10027),
making troubleshooting failures quite hard.

Apparently the only officially supported way to run the XAML compiler is through MSBuild;
so a possible approach to get run it in a supported fashion could be to generate a wrapper
MSBuild project to run it.

Standalone XAML support is C++/WinRT-specific, not a replacement for managed XAML
SDK projects. Provider templates now use the explicit namespace and saved compiler
state is target-specific; complete native-XAML dependency/output coverage is not
established by the synthetic generator tests.

# Acknowledgements

Shout out to GitHub user [DarranRowe](https://github.com/DarranRowe) who
[shared his own experience with running the standalone XamlCompiler](https://github.com/microsoft/microsoft-ui-xaml/issues/10027#issuecomment-2381644081),
making it vastly easier for me to build the required CMake logic.
