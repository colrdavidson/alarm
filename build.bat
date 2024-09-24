@echo off

taskkill /T /IM alarm.exe 2>nul >nul

rmdir /s /q bin
md bin


if "%1"=="release" (
    odin build src -out:bin\alarm.exe -debug -o:speed -no-bounds-check -subsystem:windows -define:GL_DEBUG=false -resource:resources\alarm.rc
) else if "%1"=="opt" (
    odin build src -out:bin\alarm.exe -debug -o:speed -resource:resources\alarm.rc
) else (
    odin build src -out:bin\alarm.exe -debug -keep-temp-files -resource:resources\alarm.rc
)

copy resources\SDL2.dll bin\ 2>nul >nul
