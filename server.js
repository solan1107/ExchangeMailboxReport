const http = require("http");
const fs = require("fs");
const path = require("path");

const PORT = 3099;
const BIND = process.argv[2] || "127.0.0.1";
const ROOT = __dirname;
const DATA_DIR  = path.join(ROOT, "data");
const DATA_FILE = path.join(DATA_DIR, "mailboxes.json");
const SUMMARY_FILE = path.join(DATA_DIR, "summary.json");

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".js":   "application/javascript; charset=utf-8",
  ".css":  "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png":  "image/png",
  ".ico":  "image/x-icon",
};

function serveFile(res, filePath) {
  const ext = path.extname(filePath);
  const ct  = MIME[ext] || "application/octet-stream";
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(404); res.end("Not Found"); return; }
    res.writeHead(200, { "Content-Type": ct });
    res.end(data);
  });
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = "";
    req.on("data", chunk => body += chunk);
    req.on("end", () => {
      try { resolve(JSON.parse(body)); } catch(e) { reject(new Error("Invalid JSON")); }
    });
    req.on("error", reject);
  });
}

const server = http.createServer(async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.writeHead(204); res.end();
    return;
  }

  const url = new URL(req.url, `http://localhost:${PORT}`);
  const route = url.pathname;

  // POST /api/upload — 接收 Exchange 推送的数据
  if (route === "/api/upload" && req.method === "POST") {
    try {
      const data = await parseBody(req);

      if (data.mailboxes) {
        fs.writeFileSync(DATA_FILE, JSON.stringify(data.mailboxes, null, 2), "utf-8");
      }

      let summary = data.summary || {};
      if (!summary.updateTime) {
        summary.updateTime = new Date().toLocaleString("zh-CN", { hour12: false });
      }
      if (!summary.total && data.mailboxes) {
        summary.total = data.mailboxes.length;
      }
      fs.writeFileSync(SUMMARY_FILE, JSON.stringify(summary, null, 2), "utf-8");

      console.log(`[${new Date().toISOString()}] 数据已更新: ${summary.total || "?"} 个邮箱`);

      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ message: "ok", total: summary.total }));
      return;
    } catch(e) {
      res.writeHead(400, { "Content-Type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ error: e.message }));
      return;
    }
  }

  // GET /api/mailboxes
  if (route === "/api/mailboxes") {
    fs.readFile(DATA_FILE, "utf-8", (err, data) => {
      if (err) { res.writeHead(500); res.end(JSON.stringify({ error: "No data yet." })); return; }
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(data);
    });
    return;
  }

  // GET /api/summary
  if (route === "/api/summary") {
    fs.readFile(SUMMARY_FILE, "utf-8", (err, data) => {
      if (err) { res.writeHead(500); res.end(JSON.stringify({ error: "No summary yet." })); return; }
      res.writeHead(200, { "Content-Type": "application/json; charset=utf-8" });
      res.end(data);
    });
    return;
  }

  // Static files
  let filePath = path.join(ROOT, route === "/" ? "index.html" : route);
  serveFile(res, filePath);
});

server.listen(PORT, BIND, () => {
  const addr = BIND === "0.0.0.0" ? "0.0.0.0 (所有网卡)" : BIND;
  console.log(`Exchange mailbox dashboard backend started on ${BIND}:${PORT}`);
  console.log(`Data directory: ${DATA_DIR}`);
  if (BIND === "0.0.0.0") {
    const os = require("os");
    const ifaces = os.networkInterfaces();
    for (const name of Object.keys(ifaces)) {
      for (const iface of ifaces[name]) {
        if (iface.family === "IPv4" && !iface.internal) {
          console.log(`  访问地址: http://${iface.address}:${PORT}`);
        }
      }
    }
  }
});
