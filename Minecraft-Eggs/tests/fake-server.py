import sys, threading, http.server

# Fake MC-style server for panel-lifecycle tests.
# Reads its console (stdin) like a java server, echoes every line back with a
# CONSOLE-ECHO: prefix, and serves HTTP on the given port.
def reader():
    for line in sys.stdin:
        print("CONSOLE-ECHO:" + line.strip(), flush=True)

threading.Thread(target=reader, daemon=True).start()
port = int(sys.argv[1])
httpd = http.server.ThreadingHTTPServer(("0.0.0.0", port), http.server.SimpleHTTPRequestHandler)
print("TEST-SERVER-UP port " + str(port), flush=True)
httpd.serve_forever()
