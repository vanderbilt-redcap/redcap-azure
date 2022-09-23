#
# cronWebJob.ps1
#

$cronFile = "$($env:HOME)\site\wwwroot\cron.php"

# clear out all variables just in case
Remove-Variable phpGenericExe,phpExe,phpMatchPath,phpMatchExe -ErrorAction SilentlyContinue

# auto-fetch path to currently installed PHP executabe by parsing the PATH environment variable. 
# (this works b/c when the PHP version is updated, the App Service correspondingly updates the PATH variable with updated PHP version path)
$phpGenericExe = "${env:ProgramFiles}\PHP\v7.3\php.exe"
$phpMatchPath = $($(${Env:PATH} -split ";") -match "\\PHP\\v")
$phpMatchExe = Join-Path -Path $phpMatchPath -ChildPath "php.exe"

# use path only if it exists, otherwise use generic/hard-coded path
$phpExe = @($phpMatchExe,$phpGenericExe)[!$(Test-Path -path $phpMatchExe)]

Start-Process -NoNewWindow -FilePath $phpExe -ArgumentList @($cronFile)
