@echo off
echo -- PureSQL UnitTesting build > Release.sql
echo -->> Release.sql
echo -- Don't edit this file directly. Edit individual .sql files in /procs and run build.bat>> Release.sql
echo.>> Release.sql
echo go>> Release.sql
echo.>> Release.sql
type .\procs\*.sql >> Release.sql