Canister
========

A micro, around 100 lines, of pure PowerShell standalone webserver designed to create RESTful APIs. Embed it in your application to create responsive AJAX and Single Page Applications. Also serves files like a regular web server to bootstrap the application. Logs access in Normal log Format. Does not need IIS.

Setup
-----
Requires PowerShell 3.0 or better, and .Net 4.5 or better. Enable your Windows system to run PowerShell scripts by running the following command on a privileged command prompt:

    powershell set-executionpolicy unrestricted
    
Allow using a TCP/IP port for HTTP on your system by running the following command on a privileged command prompt:

    netssh http add urlacl url=http://+:8000/ user=myComputername\myUsername
    
Optionally permit inbound port TCP 8000 on Windows Firewall to use the web server from other computers.

Test Drive
----------
Run the sample.ps1 script. From any web browser on the same computer browse to the following:

    http://localhost:8000/hello
    http://localhost:8000

Creating Apps with Canister
---------------------------
Web applications are made up of two parts: the server side, or back end, and the user side, or the front end. The front end runs within the browser and its main job is to provide a graphical user interface. The front end commnunicates with the back end to retrieve files and data. The front end application itself is contained within certain files, such as index.html, so the back end has to serve at least those files to the browser to start, or boot, the front end. Once the front end starts it can ask for files such as HTML documents, or data using AJAX architecture. Modern front ends try to minimize asking for files; they paint relevant views by only exchanging data with the back end. These applications are sometimes known as Single Page Applications or SPA. Because files are not transmitted everytime user makes a selection or enters data, such applications are very responsive.

Canister provides the back end for web applications. It can serve files like a traditional web server, but it's main goal is to service AJAX data requests.

A Canister application is a regular PowerShell script with functions or named script blocks. Some or all of these functions can be wired into Canister such that these can be called by the front end.

Handlers
--------
Routes
------
A route is the text after the server name and optional port number, and before any query string in a URL. For example in the URL http://myserver.mydomain.com:8000/images/getimage?name=cat.jpg, the route is /images/getimage. Each Canister handler is wired to a specific route. The route specification is a .Net regular Expression. Thus '^/' will match all routes. If multiple handlers match the route specification, only the first will be executed. Thus the order of handlers is significant. The best practice is to start with handlers with most specific route, and the last one should handle '^/'.

Method
------
