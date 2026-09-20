import json
import os
import socket
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

class ServiceHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/':
            app_name = os.environ.get('APP_NAME', 'demo-app')
            version = os.environ.get('VERSION', '1.0.0')
            pod_name = os.environ.get('HOSTNAME', socket.gethostname())
            
            response_data = {
                "app": app_name,
                "version": version,
                "pod": pod_name
            }
            body = json.dumps(response_data, indent=2).encode('utf-8')
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        elif self.path == '/healthz':
            body = b'ok\n'
            self.send_response(200)
            self.send_header('Content-Type', 'text/plain')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/plain')
            body = b'Not Found\n'
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, format, *args):
        sys.stdout.write(f"[{self.log_date_time_string()}] {self.address_string()} - {format % args}\n")
        sys.stdout.flush()

def run():
    port = int(os.environ.get('PORT', 8080))
    server_address = ('0.0.0.0', port)
    httpd = HTTPServer(server_address, ServiceHandler)
    print(f"Service running on port {port}...")
    sys.stdout.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    httpd.server_close()

if __name__ == '__main__':
    run()
