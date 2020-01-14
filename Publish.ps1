

####################################
# Author:       Eric Austin
# Create date:  December 2019
# Description:  Used to automate the website publishing process (script goes in the Visual Studio website project directory and run from there)
# Notes:        Don't stop the website in IIS since that prevents the app_offline.html page from displaying
#               The presence of app_offline.html results in a user having to refresh the page anyways so there's no danger in anything user-related inadvertently surviving the publish
####################################

#set common variables
$CurrentDirectory=if ($PSScriptRoot -ne "") {$PSScriptRoot} else {(Get-Location).Path}
$ErrorActionPreference="Stop"
$PublishLogData=@()
$PublishLogLocation="$CurrentDirectory\PublishLog.csv"

#script variables
$WebsiteURL=""
$WebsiteDirectory=""

Try {

    #ensure variables are populated
    if ([string]::IsNullOrWhiteSpace($WebsiteURL) -or [string]::IsNullOrWhiteSpace($WebsiteDirectory)) {
        Throw "Ensure all script variables are populated. Publish aborted."
    }

    #ensure the project builds successfully
    Write-Host "Ensuring project builds successfully..."
    dotnet build | Out-Null
    If ($LASTEXITCODE -ne 0) {
        Throw "dotnet build did not return a success code of 0"
    }
    
    #change location to specified website directory
    Write-Host "Switching to $($WebsiteDirectory)..."
    Set-Location $WebsiteDirectory | Out-Null

    #create app_offline.htm if it doesn't already exist (this can happen sometimes when performing multiple publishes in a short amount of time, ie for troubleshooting)
    if (Test-Path -Path ".\app_offline.htm"){
        Write-Host "app_offline.htm already present, will not try to create a new one"
    }
    else {
        Write-Host "Creating app_offline.htm..."
        New-Item -ItemType "File" -Name "app_offline.htm" -Value "Website is offline for maintenance and will be available again shortly." | Out-Null
    }
    
    #give IIS a few seconds to respond to the app_offline.htm file
    Write-Host "Allowing IIS time to respond to app_offline.htm..."
    Start-Sleep -Seconds 5

    #delete directory contents
    Write-Host "Deleting website directory contents except for app_offline.htm..."
    Get-ChildItem | Where-Object Name -NE "app_offline.htm" | ForEach-Object {
        Remove-Item -Path $_.FullName -Recurse -Force
    }

    #change location to the project directory
    Write-Host "Switching to $($CurrentDirectory)..."
    Set-Location $CurrentDirectory | Out-Null

    #publish site
    Write-Host "Publishing site..."
    dotnet publish -o $WebsiteDirectory | Out-Null
    If ($LASTEXITCODE -ne 0) {
        Throw "dotnet publish did not return a success code of 0"
    }

    #change location to specified website directory
    Write-Host "Switching to $($WebsiteDirectory)..."
    Set-Location $WebsiteDirectory | Out-Null
    
    #remove app_offline.htm (only remove it here, don't remove it in the catch or finally blocks, if something goes wrong at least the app_offline.htm file will still display)
    Write-Host "Removing app_offline.htm..."
    Get-ChildItem | Where-Object Name -EQ "app_offline.htm" | ForEach-Object {
        Remove-Item -Path $_.FullName
    }

    #set publish log message
    $PublishLogData+=New-Object -TypeName PSCustomObject -Property @{"Date"=(Get-Date).ToString(); "Result"="Success"; "Message"=""}
    
    #open website
    Write-Host "Publish succeeded, opening website..."
    Start-Process $WebsiteURL

}

Catch {

    #set publish log message
    $PublishLogData+=New-Object -TypeName PSCustomObject -Property @{"Date"=(Get-Date).ToString(); "Result"="Failed"; Message=$Error[0]}
    Write-Host "Publish failed, error message follows..."
    Write-Host $Error[0]

}

Finally {

    $PublishLogData | Select-Object Date, Result, Message | Export-Csv -Path $PublishLogLocation -Append -NoTypeInformation
    Pause

}