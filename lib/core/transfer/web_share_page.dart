import 'dart:convert';

/// Text for the browser page. Built from the app's ARB strings, so the page is
/// localized like the rest of the app.
class WebPageStrings {
  const WebPageStrings({
    required this.title,
    required this.warning,
    required this.downloads,
    required this.uploads,
    required this.choose,
    required this.send,
    required this.waiting,
    required this.done,
    required this.declined,
    required this.busy,
    required this.failed,
    required this.pin,
    required this.noFiles,
  });

  final String title;
  final String warning;
  final String downloads;
  final String uploads;
  final String choose;
  final String send;
  final String waiting;
  final String done;
  final String declined;
  final String busy;
  final String failed;
  final String pin;
  final String noFiles;

  Map<String, String> toJson() => {
    'title': title,
    'warning': warning,
    'downloads': downloads,
    'uploads': uploads,
    'choose': choose,
    'send': send,
    'waiting': waiting,
    'done': done,
    'declined': declined,
    'busy': busy,
    'failed': failed,
    'pin': pin,
    'noFiles': noFiles,
  };
}

/// JSON that is safe to place inside a `<script>` element. A device name such
/// as `</script><script>...` must not be able to end the script early.
String scriptSafeJson(Object? value) {
  // Each character becomes a JSON unicode escape (backslash, u, four hex
  // digits). It still means the same thing to JSON, but is inert in HTML.
  const unsafe = <int>[0x3c, 0x3e, 0x26, 0x2028, 0x2029];
  var text = jsonEncode(value);
  for (final code in unsafe) {
    final escape = '${String.fromCharCode(0x5c)}u${code.toRadixString(16).padLeft(4, '0')}';
    text = text.replaceAll(String.fromCharCode(code), escape);
  }
  return text;
}

/// The single page served to browsers. It loads nothing from the internet and
/// puts every piece of text in through `textContent`, never as HTML.
String buildWebSharePage({
  required WebPageStrings strings,
  required String deviceName,
  required bool rtl,
}) {
  final data = scriptSafeJson({'s': strings.toJson(), 'device': deviceName});
  return '''<!doctype html>
<html lang="${rtl ? 'ar' : 'en'}" dir="${rtl ? 'rtl' : 'ltr'}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Zajel</title>
<style>
:root { --bg:#0E1116; --surface:#171B22; --primary:#C6F432; --secondary:#38BDF8;
        --error:#F43F5E; --text:#E8EAED; --radius:20px; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text);
       font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
main { max-width:560px; margin:0 auto; padding:20px; }
h1 { font-size:1.4rem; margin:.2em 0 .6em; }
h2 { font-size:1.1rem; margin:0 0 .6em; }
.warn { background:#3a1d24; border:1px solid var(--error); border-radius:var(--radius);
        padding:12px 16px; margin-bottom:16px; }
section { background:var(--surface); border-radius:var(--radius); padding:18px; margin-bottom:16px; }
button, label.btn { display:block; width:100%; padding:14px; border:0; border-radius:var(--radius);
        font-size:1rem; font-weight:700; text-align:center; cursor:pointer; margin-top:10px; }
button.primary { background:var(--primary); color:var(--bg); }
label.btn { background:var(--secondary); color:var(--bg); }
button:disabled { opacity:.5; cursor:default; }
input[type=file] { display:none; }
ul { list-style:none; padding:0; margin:0; }
li { padding:10px 0; border-top:1px solid #262c36; word-break:break-word; }
li a { color:var(--secondary); text-decoration:none; }
.size { opacity:.7; font-size:.85rem; }
progress { width:100%; height:8px; margin-top:6px; }
#status { margin-top:10px; min-height:1.4em; }
.err { color:var(--error); }
</style>
</head>
<body>
<main>
  <h1 id="title"></h1>
  <div class="warn" id="warning"></div>
  <section id="downloads-box" hidden>
    <h2 id="downloads-title"></h2>
    <ul id="downloads"></ul>
  </section>
  <section>
    <h2 id="uploads-title"></h2>
    <label class="btn" for="picker" id="choose"></label>
    <input id="picker" type="file" multiple>
    <ul id="picked"></ul>
    <button class="primary" id="send" disabled></button>
    <div id="status"></div>
  </section>
</main>
<script>
const DATA = $data;
const S = DATA.s;
const T = new URLSearchParams(location.search).get('t') || '';
const \$ = id => document.getElementById(id);
const api = (route, extra) =>
  '/api/localsend/v2/' + route + '?t=' + encodeURIComponent(T) + (extra ? '&' + extra : '');
const fmt = n => n < 1024 ? n + ' B' : n < 1048576 ? (n/1024).toFixed(1) + ' KB'
  : n < 1073741824 ? (n/1048576).toFixed(1) + ' MB' : (n/1073741824).toFixed(2) + ' GB';

document.title = S.title;
\$('title').textContent = S.title + ' · ' + DATA.device;
\$('warning').textContent = S.warning;
\$('downloads-title').textContent = S.downloads;
\$('uploads-title').textContent = S.uploads;
\$('choose').textContent = S.choose;
\$('send').textContent = S.send;

function status(text, isError) {
  const el = \$('status');
  el.textContent = text;
  el.className = isError ? 'err' : '';
}

async function loadDownloads() {
  let res = await fetch(api('prepare-download'), { method: 'POST' });
  if (res.status === 401) {
    const pin = prompt(S.pin);
    if (!pin) return;
    res = await fetch(api('prepare-download', 'pin=' + encodeURIComponent(pin)), { method: 'POST' });
  }
  if (!res.ok) return;
  const body = await res.json();
  const files = Object.values(body.files || {});
  if (files.length === 0) return;
  \$('downloads-box').hidden = false;
  const list = \$('downloads');
  for (const f of files) {
    const li = document.createElement('li');
    const a = document.createElement('a');
    a.textContent = f.fileName;
    a.href = api('download', 'sessionId=' + encodeURIComponent(body.sessionId) +
                              '&fileId=' + encodeURIComponent(f.id));
    const size = document.createElement('div');
    size.className = 'size';
    size.textContent = fmt(f.size);
    li.append(a, size);
    list.append(li);
  }
}

let chosen = [];
\$('picker').addEventListener('change', e => {
  chosen = Array.from(e.target.files);
  const list = \$('picked');
  list.replaceChildren();
  for (const f of chosen) {
    const li = document.createElement('li');
    li.textContent = f.name + ' (' + fmt(f.size) + ')';
    list.append(li);
  }
  \$('send').disabled = chosen.length === 0;
  status('');
});

function sendOne(file, sessionId, fileId, token, bar) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', api('upload', 'sessionId=' + encodeURIComponent(sessionId) +
      '&fileId=' + encodeURIComponent(fileId) + '&token=' + encodeURIComponent(token)));
    xhr.upload.onprogress = e => { if (e.lengthComputable) bar.value = e.loaded / e.total; };
    xhr.onload = () => xhr.status === 200 ? resolve() : reject(new Error('HTTP ' + xhr.status));
    xhr.onerror = () => reject(new Error('network'));
    xhr.send(file);
  });
}

\$('send').addEventListener('click', async () => {
  \$('send').disabled = true;
  const files = {};
  chosen.forEach((f, i) => {
    files['f' + i] = { id: 'f' + i, fileName: f.name, size: f.size,
                       fileType: f.type || 'application/octet-stream' };
  });
  const info = { alias: 'Browser', version: '2.0', deviceType: 'web',
                 fingerprint: 'web-' + Math.random().toString(36).slice(2),
                 port: Number(location.port) || 80, protocol: 'http' };
  const body = JSON.stringify({ info, files });
  const post = pin => fetch(api('prepare-upload', pin ? 'pin=' + encodeURIComponent(pin) : ''),
    { method: 'POST', headers: { 'Content-Type': 'application/json' }, body });
  try {
    status(S.waiting);
    let res = await post('');
    if (res.status === 401) {
      const pin = prompt(S.pin);
      if (pin) res = await post(pin);
    }
    if (res.status === 403) return status(S.declined, true);
    if (res.status === 409 || res.status === 429) return status(S.busy, true);
    if (!res.ok) return status(S.failed, true);

    const session = await res.json();
    const list = \$('picked');
    status('');
    for (let i = 0; i < chosen.length; i++) {
      const token = session.files['f' + i];
      if (!token) continue;
      const bar = document.createElement('progress');
      bar.max = 1; bar.value = 0;
      list.children[i].append(bar);
      await sendOne(chosen[i], session.sessionId, 'f' + i, token, bar);
      bar.value = 1;
    }
    status(S.done);
  } catch (e) {
    status(S.failed, true);
  } finally {
    \$('send').disabled = chosen.length === 0;
  }
});

loadDownloads();
</script>
</body>
</html>
''';
}
