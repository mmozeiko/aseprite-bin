@echo off
setlocal enabledelayedexpansion

set PATH="C:\Program Files\7-Zip";%PATH%

where /q git.exe || (
  echo ERROR: "git.exe" not found
  exit /b 1
)

if exist "%ProgramFiles%\7-Zip\7z.exe" (
  set SZIP="%ProgramFiles%\7-Zip\7z.exe"
) else (
  where /q 7za.exe || (
    echo ERROR: 7-Zip installation or "7za.exe" not found
    exit /b 1
  )
  set SZIP=7za.exe
)


rem *** Visual Studio environment ***

where /Q cl.exe || (
  set __VSCMD_ARG_NO_LOGO=1
  for /f "tokens=*" %%i in ('"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property installationPath') do set VS=%%i
  if "!VS!" equ "" (
    echo ERROR: Visual Studio installation not found
    exit /b 1
  )  
  call "!VS!\VC\Auxiliary\Build\vcvarsall.bat" amd64 || exit /b 1
)


rem *** ninja

where /q ninja.exe || (
  curl -LOsf https://github.com/ninja-build/ninja/releases/download/v1.11.0/ninja-win.zip || exit /b 1
  %SZIP% x -bb0 -y ninja-win.zip 1>nul 2>nul || exit /b 1
  del ninja-win.zip 1>nul 2>nul
)


rem *** fetch latest release version

if "%ASEPRITE_VERSION%" equ "" (
  for /F "delims=" %%v in ('"curl -sfL https://api.github.com/repos/aseprite/aseprite/releases/latest | jq .tag_name -r"') do (
    set ASEPRITE_VERSION=%%v
  )
)
echo building %ASEPRITE_VERSION%

if "%ASEPRITE_VERSION:beta=%" neq "%ASEPRITE_VERSION%" (
  set SKIA_VERSION=m124-08a5439a6b
) else (
  set SKIA_VERSION=m102-861e4743af
)


rem **** clone aseprite repo

if exist aseprite (
  pushd aseprite
  call git clean --quiet -fdx
  call git submodule foreach --recursive git clean -xfd
  call git fetch --quiet --depth=1 --no-tags origin %ASEPRITE_VERSION%:refs/remotes/origin/%ASEPRITE_VERSION% || echo "failed to fetch latest version"     && exit /b 1
  call git reset --quiet --hard origin/%ASEPRITE_VERSION%                                                     || echo "failed to update to latest version" && exit /b 1
  call git submodule update --init --recursive                                                                || echo "failed to update submodules"        && exit /b 1
  popd
) else (
  call git clone --quiet -c advice.detachedHead=false --no-tags --recursive --depth=1 -b "%ASEPRITE_VERSION%" https://github.com/aseprite/aseprite.git || echo "failed to clone repo" && exit /b 1
)
python -c "v = open('aseprite/src/ver/CMakeLists.txt').read(); open('aseprite/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '%ASEPRITE_VERSION%'[1:]))"


rem *** download skia

if not exist skia-%SKIA_VERSION% (
  mkdir skia-%SKIA_VERSION%
  pushd skia-%SKIA_VERSION%
  curl -sfLO https://github.com/aseprite/skia/releases/download/%SKIA_VERSION%/Skia-Windows-Release-x64.zip || echo failed to download skia && exit /b 1
  %SZIP% x -y Skia-Windows-Release-x64.zip
  popd
)


rem *** build aseprite

if exist build rd /s /q build

set LINK=opengl32.lib
cmake.exe                                                     ^
  -G Ninja                                                    ^
  -S aseprite                                                 ^
  -B build                                                    ^
  -DCMAKE_BUILD_TYPE=Release                                  ^
  -DCMAKE_POLICY_DEFAULT_CMP0074=NEW                          ^
  -DCMAKE_POLICY_DEFAULT_CMP0091=NEW                          ^
  -DCMAKE_POLICY_DEFAULT_CMP0092=NEW                          ^
  -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded                  ^
  -DENABLE_CCACHE=OFF                                         ^
  -DOPENSSL_USE_STATIC_LIBS=TRUE                              ^
  -DLAF_BACKEND=skia                                          ^
  -DSKIA_DIR=%CD%\skia-%SKIA_VERSION%                         ^
  -DSKIA_LIBRARY_DIR=%CD%\skia-%SKIA_VERSION%\out\Release-x64 ^
  -DSKIA_OPENGL_LIBRARY=                                      || echo failed to configure build && exit /b 1
ninja.exe -C build || echo build failed && exit /b 1


rem *** create output folder

mkdir aseprite-%ASEPRITE_VERSION%
echo # This file is here so Aseprite behaves as a portable program >aseprite-%ASEPRITE_VERSION%\aseprite.ini
xcopy /E /Q /Y aseprite\docs aseprite-%ASEPRITE_VERSION%\docs\
xcopy /E /Q /Y build\bin\aseprite.exe aseprite-%ASEPRITE_VERSION%\
xcopy /E /Q /Y build\bin\data aseprite-%ASEPRITE_VERSION%\data\

if "%GITHUB_WORKFLOW%" neq "" (
  mkdir github
  move aseprite-%ASEPRITE_VERSION% github\
  echo ASEPRITE_VERSION=%ASEPRITE_VERSION%>>%GITHUB_OUTPUT%
)
