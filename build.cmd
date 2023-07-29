@echo off
setlocal enabledelayedexpansion

set PATH="C:\Program Files\7-Zip";%PATH%

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
  7z x -bb0 -y ninja-win.zip 1>nul 2>nul || exit /b 1
  del ninja-win.zip 1>nul 2>nul
)


rem *** fetching latest release version

for /F "delims=" %%v in ('"curl -sfL https://api.github.com/repos/aseprite/aseprite/releases/latest | jq .tag_name -r"') do (
  set ASEPRITE_VERSION=%%v
)


rem **** checking if release is already built

curl -sfLo nul https://api.github.com/repos/mmozeiko/aseprite-bin/releases/tags/%ASEPRITE_VERSION%
if %ERRORLEVEL% EQU 0 (
  echo release already exists, exiting
  exit /b 0
)


rem **** cloning asesprite repo

git clone --quiet -c advice.detachedHead=false --no-tags --recursive --depth=1 -b "%ASEPRITE_VERSION%" https://github.com/aseprite/aseprite.git || echo "failed to clone repo" && exit /b 1
python -c "v = open('aseprite/src/ver/CMakeLists.txt').read(); open('aseprite/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '%ASEPRITE_VERSION%'[1:]))"


rem *** downloading skia

mkdir skia
cd skia
curl -sfLO https://github.com/aseprite/skia/releases/download/m102-861e4743af/Skia-Windows-Release-x64.zip || echo failed to download skia && exit /b 1
7z x -y Skia-Windows-Release-x64.zip
cd ..


rem *** building asesprite

set LINK=opengl32.lib
cmake                                          ^
  -G Ninja                                     ^
  -S aseprite                                  ^
  -B build                                     ^
  -DCMAKE_BUILD_TYPE=Release                   ^
  -DCMAKE_C_FLAGS="/MP"                        ^
  -DCMAKE_CXX_FLAGS="/MP"                      ^
  -DENABLE_CCACHE=OFF                          ^
  -DLAF_BACKEND=skia                           ^
  -DSKIA_DIR=%CD%\skia                         ^
  -DSKIA_LIBRARY_DIR=%CD%\skia\out\Release-x64 ^
  -DSKIA_OPENGL_LIBRARY=                        || echo failed to configure build && exit /b 1
ninja -C build || echo "build failed" && exit /b 1


rem *** creating zip file

mkdir aseprite-%ASEPRITE_VERSION%
echo # This file is here so Aseprite behaves as a portable program >aseprite-%ASEPRITE_VERSION%\aseprite.ini
xcopy /E /Q /Y aseprite\docs aseprite-%ASEPRITE_VERSION%\docs\
xcopy /E /Q /Y build\bin\aseprite.exe aseprite-%ASEPRITE_VERSION%\
xcopy /E /Q /Y build\bin\data aseprite-%ASEPRITE_VERSION%\data\
7z a -r aseprite-%ASEPRITE_VERSION%.zip aseprite-%ASEPRITE_VERSION% || echo failed to create output zip file && exit /b


echo ::set-output name=ASEPRITE_VERSION::%ASEPRITE_VERSION%
