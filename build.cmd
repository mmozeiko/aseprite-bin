@echo off
setlocal 

set PATH="C:\Program Files\7-Zip";%PATH%

echo fetching latest release version
for /F "delims=" %%v in ('"curl -sfL https://api.github.com/repos/aseprite/aseprite/releases/latest | jq .tag_name -r"') do (
  set ASEPRITE_VERSION=%%v
)


echo checking if release is already built
curl -sfLo nul https://api.github.com/repos/mmozeiko/aseprite-bin/releases/tags/%ASEPRITE_VERSION%
if %ERRORLEVEL% EQU 0 (
  echo release already exists, exiting
  exit /b 0
)


echo cloning asesprite %ASEPRITE_VERSION%
git clone --quiet -c advice.detachedHead=false --no-tags --recursive --depth=1 -b "%ASEPRITE_VERSION%" https://github.com/aseprite/aseprite.git || echo "failed to clone repo" && exit /b
python -c "v = open('aseprite/src/ver/CMakeLists.txt').read(); open('aseprite/src/ver/CMakeLists.txt', 'w').write(v.replace('1.x-dev', '%ASEPRITE_VERSION%'[1:]))"


echo downloading skia
mkdir skia
cd skia
curl -sfLO https://github.com/aseprite/skia/releases/download/m96-2f1f21b8a9/Skia-Windows-Release-x64.zip || echo failed to download skia && exit /b
7z x -y Skia-Windows-Release-x64.zip
cd ..


echo building asesprite
set LINK=opengl32.lib
cmake                                          ^
  -G "Visual Studio 16 2019"                   ^
  -A x64                                       ^
  -S aseprite                                  ^
  -B build                                     ^
  -DCMAKE_BUILD_TYPE=Release                   ^
  -DCMAKE_C_FLAGS="/MP"                        ^
  -DCMAKE_CXX_FLAGS="/MP"                      ^
  -DLAF_BACKEND=skia                           ^
  -DSKIA_DIR=%CD%\skia                         ^
  -DSKIA_LIBRARY_DIR=%CD%\skia\out\Release-x64 ^
  -DSKIA_OPENGL_LIBRARY=                        || echo failed to configure build && exit /b
python -c "v = open('build/src/aseprite.vcxproj').read(); open('build/src/aseprite.vcxproj', 'w').write(v.replace(';..\lib\..\libcurl.lib;', ';..\lib\libcurl.lib;'))"
python -c "v = open('build/src/aseprite.vcxproj').read(); open('build/src/aseprite.vcxproj', 'w').write(v.replace(';.\lib\libcurl.lib;', ';..\lib\libcurl.lib;'))"
cmake --build build --config Release -- -m -v:q || echo "build failed" && exit /b


echo creating zip file
mkdir aseprite-%ASEPRITE_VERSION%
echo # This file is here so Aseprite behaves as a portable program >aseprite-%ASEPRITE_VERSION%\aseprite.ini
xcopy /E /Q /Y aseprite\docs aseprite-%ASEPRITE_VERSION%\docs\
xcopy /E /Q /Y build\bin\aseprite.exe aseprite-%ASEPRITE_VERSION%\
xcopy /E /Q /Y build\bin\data aseprite-%ASEPRITE_VERSION%\data\
7z a -r aseprite-%ASEPRITE_VERSION%.zip aseprite-%ASEPRITE_VERSION% || echo failed to create output zip file && exit /b


echo ::set-output name=ASEPRITE_VERSION::%ASEPRITE_VERSION%
