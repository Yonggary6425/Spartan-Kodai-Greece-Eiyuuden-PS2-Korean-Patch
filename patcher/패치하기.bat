@echo off
chcp 65001 >nul
if "%~1"=="" (echo 원본 ISO 파일 또는 게임 폴더를 이 bat 파일 위에 끌어다 놓으세요.& pause & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" "%~1"
pause
