Canister
========

A micro web server written in pure PowerShell designed to create RESTful APIs. Give your PowerShell scripts a rich web interface, or create full featured enterprise apps. Perfect for home automation projects in place of native apps.

* Extremely light weight
* HTTPS supported (self-signed certificate generator and installer included)
* No runtime dependencies except Powershell 3.0 and .Net 4.5
* IIS not needed
* Will run on any Windows desktop or server
* Access to over 6,000 .Net classes, dozens of PowerShell modules created by product companies such as Vmware, database storage, as well as COM servers

Setup
-----
Requires PowerShell 3.0 or better, and .Net 4.5 or better. Enable your Windows system to run PowerShell scripts by running the following command on a privileged command prompt:

    powershell set-executionpolicy unrestricted
    
Run setup.ps1, also from privileged command prompt, to configure Windows URL reservation, generate and install a self-signed certificate, attach the certificate to the port and configure Windows firewall.

Test Drive
----------
Run the sample.ps1 script. From any web browser on the same computer browse to the following:

    http://localhost:8000/hello
    http://localhost:8000

Creating Apps with Canister
---------------------------
Web applications are made up of two parts: the server side, or back end, and the user side, or the front end. The front end runs within the browser and its main job is to provide a graphical user interface. The front end commnunicates with the back end to retrieve files and data. The front end application itself is contained within certain files, such as index.html, so the back end has to serve at least those files to the browser to start, or boot, the front end. Once the front end starts it can ask for files such as HTML documents, or data using AJAX architecture. Modern front ends try to minimize asking for files; they paint relevant views only by exchanging data with the back end. These applications are sometimes known as Single Page Applications or SPA. Because files are not transmitted everytime user makes a selection or enters data, such applications are very responsive.

Canister provides the back end for web applications. It can serve files like a traditional web server, but it's main goal is to service AJAX data requests.

A Canister application is a regular PowerShell script with functions or named script blocks. Some or all of these functions can be wired into Canister such that these can be called by the front end.

Handlers
--------
A Handler is a PowerShell function or named script block that will service certain requests from the front end. Requests are distinguished based on Route and Method. Each Handler can service only one combination of Route and Method.

Routes
------
A route is the text after the server name and optional port number, and before any query string in web browser address. For example in the address http://myserver.mydomain.com:8000/images/getimage?name=cat.jpg, the route is /images/getimage. Each Canister Handler is wired to a specific route. The route specification is a .Net regular Expression. Thus '^/' will match all routes. If multiple Handlers match the route specification, only the first will be executed. Thus the order of Handlers is significant. The best practice is to start with Handlers with most specific Route, with the last one handling '^/'.

Methods
-------
Each Canister handler must be wired to one HTTP Method in addition to a Route. The default method is GET. Other HTTP methods include POST, PUT, DELETE and HEAD.

Passing Data In and Out
-----------------------
Each Handler receives two parameters. At position 1 is [System.Net.HttpListenerRequest](http://msdn.microsoft.com/en-us/library/system.net.httplistenerrequest(v=vs.110).aspx) and at position 2 is the [System.Net.HttpListenerResponse](http://msdn.microsoft.com/en-us/library/system.net.httplistenerresponse(v=vs.110).aspx) object. The Request object can be used to extract the request and any data sent by the front end, and the Response object is used to send back any requested data to the front end. Canister extends these objects with the following conveniences:

    $request.GetBody()
Gets the body of a POST or PUT request from the front end as a string. The handler must further process this string based on $request.Headers['ContentType'] value. For example when { $request.Headers['ContentType'] -match 'application/json' } then ConvertTo-JSON cmdlet should be used on the string.

    $response.SendText($text, $contentType)
Send the text to the front end and set the HTTP Content-Type header to $contentType. The default value for $contentType is application/json.

    $response.SendFile($filename)
Sends a file to the front end. $filename should be the complete path to the file such as c:\users\me\desktop\app.html.

Canister is Single Threaded
---------------------------
While a Handler is doing it's work, other requests from the same or other front ends must wait in line. Thus Handlers must be designed to finish as quickly as possible. Long running tasks should be created as an asynchronous task (PowerShell Job or [powershell].Invoke) by the Handler. The synchronous design of Canister allows the fastest response with least overhead, while letting Handlers create asynchronous tasks as needed.
