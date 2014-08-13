$scriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition

. "$scriptPath\WebServer.ps1"

$handlers = @()


function FileServer ($request, $response) {
    if ($request.RawUrl -eq '/') { $filename = '/index.html' }
    else { $filename = $request.RawUrl }
    $filename = $filename -replace '/', '\'
    $response.SendFile($scriptPath + $filename)
}

function HelloWorld ($request, $response) {
    $response.SendText('Hello World')
}

$handlers += @{route='^/hello$'; handler='HelloWorld'; method='GET'}
$handlers += @{route='^/'; handler='FileServer'; method='GET'}
WebServer-Start -handlers $handlers -log File
