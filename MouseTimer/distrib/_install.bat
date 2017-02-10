echo off
echo Deploying project MouseTimer
IF EXIST MCRInstaller.exe (
    echo Running MCRInstaller
    MCRInstaller.exe
) ELSE IF EXIST MCRInstaller.cmd (
    echo Running remote MCRInstaller
    MCRInstaller.cmd
)

echo Installation complete.
echo Please refer to the documentation for any additional setup steps.