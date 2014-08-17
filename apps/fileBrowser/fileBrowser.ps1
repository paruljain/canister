$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

. ..\..\canister.ps1

$handlers = @()

function AppBoot ($request, $response) {
    if ($request.RawUrl -eq '/') { $filename = '/fileBrowser.html' }
    else { $filename = $request.RawUrl }
    $filename = $filename -replace '/', '\'
    $response.SendFile($scriptPath + $filename)
}

function BrowseFiles ($request, $response) {
    $path = $request.GetBody()
    $entries = @()
    $parent = split-path $path
    if ($parent) {
        $entries += @{name='..'; folder=$true; path=$parent; extension=''}
    }
    ls $path -ErrorAction Ignore | % {
        if ($_.Mode -match '^d') { $folder = $true }
        else { $folder = $false }
        $entries += @{name=$_.Name; folder=$folder; path=$_.FullName; extension=$_.Extension}
    }
    $response.SendText(($entries | ConvertTo-Json -Compress))
}

$handlers += @{route='^/browser$'; handler='BrowseFiles'; method='POST'}
$handlers += @{route='^/'; handler='AppBoot'; method='GET'}
Canister-Start -handlers $handlers -log File
