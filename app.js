const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/', (req, res) => {
  // CloudFront & ALB append IPs to X-Forwarded-For
  const xForwardedFor = req.headers['x-forwarded-for'];
  let clientIp = req.socket.remoteAddress;

  if (xForwardedFor) {
    // Take the first entry in the comma-separated list
    clientIp = xForwardedFor.split(',')[0].trim();
  }

  res.send(`
    <html>
      <head><title>IP Checker</title></head>
      <body>
        <h1>Your IP is: ${clientIp}</h1>
      </body>
    </html>
  `);
});

// Health check for ALB
app.get('/health', (req, res) => res.sendStatus(200));
app.listen(PORT, '0.0.0.0', () => {
  console.log(`App running on port ${PORT}`);
});