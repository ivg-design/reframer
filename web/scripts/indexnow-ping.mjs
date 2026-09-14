import https from "node:https";

const host = "forge.mograph.life";
const key = "reframer-indexnow-20260227";
const keyLocation = `https://${host}/apps/reframer/indexnow.txt`;
const urlList = [
  `https://${host}/apps/reframer/`,
  `https://${host}/apps/reframer/docs`,
  `https://${host}/apps/reframer/changelog`
];

const payload = JSON.stringify({
  host,
  key,
  keyLocation,
  urlList,
});

const req = https.request(
  "https://api.indexnow.org/IndexNow",
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Content-Length": Buffer.byteLength(payload),
    },
  },
  (res) => {
    console.log(`IndexNow response: ${res.statusCode}`);
    res.on("data", () => {});
  }
);

req.on("error", (err) => {
  console.error("IndexNow request failed:", err.message);
  process.exitCode = 1;
});

req.write(payload);
req.end();
