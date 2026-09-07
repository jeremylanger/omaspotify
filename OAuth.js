.pragma library
.import "Api.js" as Api

function normalizedPort(value) {
  var port = Math.floor(Number(value))
  return port >= 1024 && port <= 65535 ? port : 8989
}

function decode(value) {
  try { return decodeURIComponent(String(value || "").replace(/\+/g, " ")) }
  catch (e) { return "" }
}

function parseQuery(raw) {
  var result = {}
  var query = String(raw || "")
  if (query.charAt(0) === "?") query = query.substring(1)
  var parts = query.split("&")
  for (var i = 0; i < parts.length; i++) {
    if (!parts[i]) continue
    var separator = parts[i].indexOf("=")
    var key = separator < 0 ? parts[i] : parts[i].substring(0, separator)
    var value = separator < 0 ? "" : parts[i].substring(separator + 1)
    result[decode(key)] = decode(value)
  }
  return result
}

function parseCallbackRequestLine(line, expectedPath) {
  var match = String(line || "").match(/^GET\s+([^\s]+)\s+HTTP\/\d(?:\.\d)?$/)
  if (!match) return { ok: false, error: "Invalid OAuth callback request" }
  var target = match[1]
  var separator = target.indexOf("?")
  var path = separator < 0 ? target : target.substring(0, separator)
  var requiredPath = String(expectedPath || "/callback")
  if (path !== requiredPath) return { ok: false, error: "Unexpected OAuth callback path" }
  var values = parseQuery(separator < 0 ? "" : target.substring(separator + 1))
  if (values.error) return { ok: false, error: values.error_description || values.error, state: values.state || "" }
  if (!values.code) return { ok: false, error: "Spotify did not return an authorization code", state: values.state || "" }
  return { ok: true, code: values.code, state: values.state || "" }
}

function parsePkceOutput(line) {
  var parts = String(line || "").trim().split("\t")
  if (parts.length !== 3) return { ok: false, error: "Could not create PKCE parameters" }
  if (!/^[A-Za-z0-9._~-]{43,128}$/.test(parts[0])) return { ok: false, error: "Invalid PKCE verifier" }
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(parts[1])) return { ok: false, error: "Invalid PKCE challenge" }
  if (!/^[A-Fa-f0-9]{32,128}$/.test(parts[2])) return { ok: false, error: "Invalid OAuth state" }
  return { ok: true, verifier: parts[0], challenge: parts[1], state: parts[2] }
}

function parseTokenResponse(status, text, previousRefreshToken) {
  var payload = Api.parseJson(text, null)
  if (status < 200 || status >= 300 || !payload || !payload.access_token) {
    return {
      ok: false,
      invalidGrant: !!payload && payload.error === "invalid_grant",
      error: Api.responseError(status, payload,
        "Could not complete Spotify sign-in. Please try again")
    }
  }
  return {
    ok: true,
    accessToken: String(payload.access_token),
    refreshToken: String(payload.refresh_token || previousRefreshToken || ""),
    expiresIn: Math.max(60, Number(payload.expires_in) || 3600),
    scope: String(payload.scope || "")
  }
}

function successResponse() {
  var body = "<!doctype html><meta charset=\"utf-8\"><title>OmaSpotify</title>"
    + "<style>:root{color-scheme:light dark}body{font-family:system-ui;background:Canvas;color:CanvasText;display:grid;place-items:center;height:100vh;margin:0}"
    + "main{max-width:32rem;padding:2rem;border:1px solid GrayText;border-radius:.5rem}</style>"
    + "<main><h1>Authorization complete</h1><p>Returning to OmaSpotify…</p>"
    + "<p><small>If this tab stays open, it is safe to close.</small></p></main>"
    + "<script>setTimeout(function(){window.close()},150)</script>"
  return "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: "
    + body.length + "\r\nConnection: close\r\n\r\n" + body
}

function failureResponse() {
  var body = "<!doctype html><meta charset=\"utf-8\"><title>Authorization failed</title>"
    + "<p>Authorization failed. Return to Omarchy for details.</p>"
  return "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: "
    + body.length + "\r\nConnection: close\r\n\r\n" + body
}
