from flask import Flask, jsonify
import socket
import os

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify({
        "message": "Hello from Zero Trust Platform!",
        "hostname": socket.gethostname(),
        "pod_ip": os.environ.get("POD_IP", "unknown")
    })

@app.route("/healthz")
def healthz():
    return jsonify({"status": "ok"})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)