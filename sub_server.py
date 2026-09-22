#!/usr/bin/env python3
"""
VPN Subscription Web Dashboard & Local Subscription Server
==========================================================
Обеспечивает локальный веб-интерфейс и точку раздачи подписки /sub
для клиентов v2rayN, v2rayNG, Happ, Hiddify, Streisand, NekoBox и др.
"""

import os
import sys
import json
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from vpn_finder import (
    SubscriptionAnalyzer,
    WorkingSubscriptionFinder,
    encode_base64_subscription,
    COUNTRY_FLAGS
)

PORT = 8080

HTML_PAGE = """<!DOCTYPE html>
<html lang="ru">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VPN Subscription Finder & Checker</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&family=Outfit:wght@300;400;600;700;800&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #090d16;
      --card-bg: rgba(18, 24, 38, 0.75);
      --card-border: rgba(255, 255, 255, 0.08);
      --accent-cyan: #00f2fe;
      --accent-blue: #4facfe;
      --accent-green: #00f5a0;
      --accent-red: #ff3366;
      --accent-orange: #ff9900;
      --accent-purple: #9d4edd;
      --text: #e2e8f0;
      --text-muted: #94a3b8;
    }

    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: radial-gradient(circle at 10% 20%, #0d1527 0%, var(--bg) 90%);
      color: var(--text);
      font-family: 'Outfit', sans-serif;
      min-height: 100vh;
      padding: 30px 20px;
    }

    .container {
      max-width: 1100px;
      margin: 0 auto;
    }

    header {
      text-align: center;
      margin-bottom: 35px;
    }

    .badge {
      display: inline-block;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 1px;
      background: rgba(0, 242, 254, 0.15);
      color: var(--accent-cyan);
      border: 1px solid rgba(0, 242, 254, 0.3);
      margin-bottom: 12px;
    }

    h1 {
      font-size: 34px;
      font-weight: 800;
      background: linear-gradient(135deg, #ffffff 0%, var(--accent-cyan) 60%, var(--accent-blue) 100%);
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      margin-bottom: 8px;
    }

    p.subtitle {
      color: var(--text-muted);
      font-size: 15px;
    }

    .card {
      background: var(--card-bg);
      backdrop-filter: blur(16px);
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 24px;
      margin-bottom: 24px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.3);
    }

    .input-group {
      display: flex;
      gap: 12px;
      margin-bottom: 12px;
    }

    input[type="text"] {
      flex: 1;
      background: rgba(10, 14, 23, 0.8);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 10px;
      padding: 14px 16px;
      color: #fff;
      font-family: 'JetBrains Mono', monospace;
      font-size: 14px;
      outline: none;
      transition: all 0.2s;
    }

    input[type="text"]:focus {
      border-color: var(--accent-cyan);
      box-shadow: 0 0 15px rgba(0, 242, 254, 0.25);
    }

    .btn {
      background: linear-gradient(135deg, var(--accent-blue) 0%, var(--accent-cyan) 100%);
      color: #050b14;
      font-weight: 700;
      font-size: 14px;
      padding: 14px 24px;
      border: none;
      border-radius: 10px;
      cursor: pointer;
      display: flex;
      align-items: center;
      gap: 8px;
      transition: transform 0.15s, box-shadow 0.15s;
    }

    .btn:hover {
      transform: translateY(-2px);
      box-shadow: 0 6px 20px rgba(0, 242, 254, 0.4);
    }

    .btn:active { transform: translateY(0); }

    .btn-secondary {
      background: rgba(255, 255, 255, 0.08);
      color: #fff;
      border: 1px solid rgba(255, 255, 255, 0.15);
    }

    .btn-secondary:hover {
      background: rgba(255, 255, 255, 0.15);
      box-shadow: none;
    }

    .quick-links {
      font-size: 13px;
      color: var(--text-muted);
      display: flex;
      align-items: center;
      gap: 8px;
      flex-wrap: wrap;
    }

    .quick-link-btn {
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.1);
      color: var(--accent-cyan);
      padding: 4px 10px;
      border-radius: 6px;
      cursor: pointer;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
    }

    .quick-link-btn:hover {
      background: rgba(0, 242, 254, 0.15);
    }

    /* Diagnosis Section */
    .diag-box {
      border-left: 4px solid var(--accent-orange);
      background: rgba(255, 153, 0, 0.08);
      padding: 16px;
      border-radius: 8px;
      margin-top: 20px;
      display: none;
    }

    .diag-box.error {
      border-left-color: var(--accent-red);
      background: rgba(255, 51, 102, 0.08);
    }

    .diag-box.success {
      border-left-color: var(--accent-green);
      background: rgba(0, 245, 160, 0.08);
    }

    .diag-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 12px;
      margin-top: 12px;
    }

    .diag-item {
      background: rgba(0, 0, 0, 0.25);
      padding: 10px;
      border-radius: 8px;
      font-size: 13px;
    }

    .diag-label {
      color: var(--text-muted);
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
    }

    .diag-val {
      font-weight: 700;
      margin-top: 4px;
      font-family: 'JetBrains Mono', monospace;
    }

    /* Sub Endpoint Card */
    .sub-endpoint-card {
      background: linear-gradient(135deg, rgba(79, 172, 254, 0.15) 0%, rgba(0, 242, 254, 0.05) 100%);
      border: 1px solid rgba(79, 172, 254, 0.3);
      display: flex;
      justify-content: space-between;
      align-items: center;
      flex-wrap: wrap;
      gap: 16px;
    }

    .sub-url-box {
      font-family: 'JetBrains Mono', monospace;
      background: rgba(0, 0, 0, 0.4);
      padding: 10px 14px;
      border-radius: 8px;
      font-size: 13px;
      color: var(--accent-cyan);
      border: 1px dashed rgba(0, 242, 254, 0.4);
      word-break: break-all;
    }

    /* Table */
    .table-container {
      overflow-x: auto;
      margin-top: 15px;
    }

    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }

    th {
      text-align: left;
      padding: 12px 14px;
      background: rgba(255, 255, 255, 0.03);
      color: var(--text-muted);
      font-weight: 600;
      border-bottom: 1px solid var(--card-border);
      text-transform: uppercase;
      font-size: 11px;
      letter-spacing: 0.5px;
    }

    td {
      padding: 12px 14px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.04);
      font-family: 'JetBrains Mono', monospace;
    }

    tr:hover td {
      background: rgba(255, 255, 255, 0.03);
    }

    .proto-tag {
      padding: 3px 8px;
      border-radius: 4px;
      font-weight: 700;
      font-size: 11px;
    }
    .proto-vless { background: rgba(0, 242, 254, 0.15); color: var(--accent-cyan); }
    .proto-trojan { background: rgba(157, 78, 221, 0.15); color: var(--accent-purple); }
    .proto-vmess { background: rgba(255, 153, 0, 0.15); color: var(--accent-orange); }
    .proto-hy2, .proto-hysteria2 { background: rgba(0, 245, 160, 0.15); color: var(--accent-green); }

    .ping-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      font-weight: 700;
      color: var(--accent-green);
    }

    .ping-dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--accent-green);
      box-shadow: 0 0 8px var(--accent-green);
    }

    .action-btn {
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.15);
      color: #fff;
      padding: 6px 12px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 12px;
      transition: all 0.15s;
    }

    .action-btn:hover {
      background: var(--accent-cyan);
      color: #000;
    }

    /* Educational Box */
    .edu-box {
      background: rgba(13, 22, 38, 0.6);
      border-left: 4px solid var(--accent-blue);
      padding: 16px;
      border-radius: 8px;
      font-size: 13px;
      line-height: 1.6;
    }

    .edu-box h4 {
      color: var(--accent-cyan);
      margin-bottom: 6px;
    }

    /* Modal */
    .modal {
      display: none;
      position: fixed;
      top: 0; left: 0; right: 0; bottom: 0;
      background: rgba(0,0,0,0.8);
      backdrop-filter: blur(5px);
      z-index: 1000;
      justify-content: center;
      align-items: center;
    }

    .modal-content {
      background: #0f172a;
      border: 1px solid var(--card-border);
      border-radius: 16px;
      padding: 24px;
      max-width: 480px;
      width: 90%;
      text-align: center;
      box-shadow: 0 20px 50px rgba(0,0,0,0.6);
    }

    .qr-container {
      background: #fff;
      padding: 16px;
      border-radius: 12px;
      display: inline-block;
      margin: 16px 0;
    }

    .toast {
      position: fixed;
      bottom: 24px;
      right: 24px;
      background: #00f5a0;
      color: #000;
      padding: 12px 20px;
      border-radius: 8px;
      font-weight: 700;
      font-size: 14px;
      box-shadow: 0 10px 25px rgba(0, 245, 160, 0.4);
      display: none;
      z-index: 2000;
    }
  </style>
</head>
<body>

<div class="container">
  <header>
    <div class="badge">V2Ray / VLESS / Reality / Trojan / VMess</div>
    <h1>VPN Subscription Finder & Checker</h1>
    <p class="subtitle">Анализ подписок, диагностика лимитов ботов и сборка проверенных рабочих серверов</p>
  </header>

  <!-- Input Form -->
  <div class="card">
    <div class="input-group">
      <input type="text" id="targetUrl" placeholder="Вставьте ссылку на подписку VPN (например https://myvpnkey.com/sub/...)" value="https://myvpnkey.com/sub/sub_b44503f8936a8be5c1567f4470c2dfc6">
      <button class="btn" id="analyzeBtn" onclick="runAnalysis()">
        <svg width="18" height="18" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
        Найти рабочие
      </button>
    </div>

    <div class="quick-links">
      <span>Примеры ссылок:</span>
      <button class="quick-link-btn" onclick="setExample('https://myvpnkey.com/sub/sub_b44503f8936a8be5c1567f4470c2dfc6')">myvpnkey.com (MellVPN)</button>
      <button class="quick-link-btn" onclick="setExample('https://raw.githubusercontent.com/vorz1k/v2box/main/supreme_vpns_1.txt')">Vorz1k VLESS Feed</button>
      <button class="quick-link-btn" onclick="setExample('https://raw.githubusercontent.com/barry-far/V2ray-config/main/Splitted-By-Protocol/trojan.txt')">Barry-far Trojan</button>
    </div>

    <!-- Diagnostic Box -->
    <div class="diag-box" id="diagBox">
      <div style="display:flex; justify-content:space-between; align-items:center;">
        <h3 id="diagTitle" style="font-size:16px;">Результат диагностики ссылки</h3>
        <span class="badge" id="diagStatusBadge">EXPIRED</span>
      </div>
      <div class="diag-grid">
        <div class="diag-item">
          <div class="diag-label">Провайдер / Домен</div>
          <div class="diag-val" id="diagDomain">-</div>
        </div>
        <div class="diag-item">
          <div class="diag-label">Обнаружен бот</div>
          <div class="diag-val" id="diagBot">-</div>
        </div>
        <div class="diag-item">
          <div class="diag-label">Рабочих узлов</div>
          <div class="diag-val" id="diagWorkingCount">0</div>
        </div>
        <div class="diag-item">
          <div class="diag-label">Ошибки / Заглушки</div>
          <div class="diag-val" id="diagDummyCount">0</div>
        </div>
      </div>
      <div id="diagErrors" style="margin-top:12px; font-size:13px; color:#ff9900;"></div>
    </div>
  </div>

  <!-- Educational Info Box -->
  <div class="card edu-box">
    <h4>💡 Почему исходная ссылка не работает и как работает подбор?</h4>
    <p>
      Ссылка <code>myvpnkey.com/sub/sub_b44503f8936a8be5c1567f4470c2dfc6</code> принадлежит боту <b>@TheMellVpnBot</b>.
      Она вернула заглушки на <code>127.0.0.1</code> с сообщением <i>"⚠️ У вас лимит устройств"</i>.
      Токен <code>b44503f8936a8be5c1567f4470c2dfc6</code> — это 128-битный хэш ($16^{32}$ вариантов), поэтому угадать чужой токен «вслепую» математически невозможно, а сервер забанит IP за частые запросы.
      <b>Наш инструмент решает задачу правильно:</b> он проверяет статус переданного сервиса, обращается к проверенным пулам и зеркалам (VLESS Reality, VMess, Trojan), фильтрует нерабочие узлы быстрым пинг-тестом и формирует для вас готовую рабочую подписку!
    </p>
  </div>

  <!-- Live Sub Endpoint -->
  <div class="card sub-endpoint-card">
    <div>
      <div style="font-size:12px; text-transform:uppercase; letter-spacing:1px; color:var(--accent-cyan); font-weight:700;">Ссылка на автообновляемую подписку для клиента:</div>
      <div class="sub-url-box" id="subUrl">http://127.0.0.1:8080/sub</div>
    </div>
    <div style="display:flex; gap:10px;">
      <button class="btn" onclick="copySubUrl()">📋 Скопировать ссылку</button>
      <button class="btn btn-secondary" onclick="copyBase64()">🔑 Скопировать Base64</button>
      <button class="btn btn-secondary" onclick="showQrModal()">📱 QR-код</button>
    </div>
  </div>

  <!-- Working Nodes List -->
  <div class="card">
    <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:12px;">
      <div>
        <h2 style="font-size:20px;">Рабочие проверенные серверы</h2>
        <p style="color:var(--text-muted); font-size:13px;" id="nodesCountDesc">Загрузка серверов...</p>
      </div>
      <div style="display:flex; gap:8px;">
        <button class="action-btn" onclick="filterProto('all')">Все</button>
        <button class="action-btn" onclick="filterProto('vless')">VLESS</button>
        <button class="action-btn" onclick="filterProto('trojan')">Trojan</button>
        <button class="action-btn" onclick="filterProto('vmess')">VMess</button>
        <button class="action-btn" onclick="filterProto('hy2')">Hy2</button>
      </div>
    </div>

    <div class="table-container">
      <table>
        <thead>
          <tr>
            <th>№</th>
            <th>Протокол</th>
            <th>Пинг</th>
            <th>Страна</th>
            <th>Сервер / Порт</th>
            <th>Название</th>
            <th>Действие</th>
          </tr>
        </thead>
        <tbody id="nodesTableBody">
          <!-- Populated by JS -->
        </tbody>
      </table>
    </div>
  </div>
</div>

<!-- Modal QR Code -->
<div class="modal" id="qrModal" onclick="closeQrModal(event)">
  <div class="modal-content" onclick="event.stopPropagation()">
    <h3 style="font-size:18px; margin-bottom:8px;">Импорт в мобильное приложение</h3>
    <p style="color:var(--text-muted); font-size:13px;">Отсканируйте камерой в <b>Happ</b>, <b>v2rayNG</b>, <b>Hiddify</b>, <b>Streisand</b> или <b>NekoBox</b></p>
    <div class="qr-container">
      <img id="qrImg" src="" alt="QR Code" width="220" height="220">
    </div>
    <br>
    <button class="btn" style="margin:0 auto;" onclick="document.getElementById('qrModal').style.display='none'">Закрыть</button>
  </div>
</div>

<div class="toast" id="toast">Скопировано в буфер обмена!</div>

<script>
  let allWorkingNodes = [];
  let currentBase64Sub = "";

  function setExample(url) {
    document.getElementById('targetUrl').value = url;
    runAnalysis();
  }

  function showToast(text) {
    const t = document.getElementById('toast');
    t.innerText = text || 'Скопировано в буфер обмена!';
    t.style.display = 'block';
    setTimeout(() => { t.style.display = 'none'; }, 2200);
  }

  function copySubUrl() {
    const url = document.getElementById('subUrl').innerText;
    navigator.clipboard.writeText(url).then(() => showToast('Ссылка на подписку скопирована!'));
  }

  function copyBase64() {
    if (!currentBase64Sub) return;
    navigator.clipboard.writeText(currentBase64Sub).then(() => showToast('Base64 подписка скопирована!'));
  }

  function copyNode(raw) {
    navigator.clipboard.writeText(raw).then(() => showToast('Конфигурация сервера скопирована!'));
  }

  function showQrModal(raw) {
    const dataToEncode = raw || document.getElementById('subUrl').innerText;
    const qrUrl = 'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=' + encodeURIComponent(dataToEncode);
    document.getElementById('qrImg').src = qrUrl;
    document.getElementById('qrModal').style.display = 'flex';
  }

  function closeQrModal(e) {
    document.getElementById('qrModal').style.display = 'none';
  }

  function renderTable(nodes) {
    const tbody = document.getElementById('nodesTableBody');
    tbody.innerHTML = '';
    nodes.forEach((node, idx) => {
      const tr = document.createElement('tr');
      const protoClass = 'proto-' + node.proto.toLowerCase();
      const flag = getFlag(node.country);
      tr.innerHTML = `
        <td style="color:var(--text-muted);">${idx + 1}</td>
        <td><span class="proto-tag ${protoClass}">${node.proto.toUpperCase()}</span></td>
        <td>
          <div class="ping-badge">
            <div class="ping-dot"></div>
            <span>${Math.round(node.ping_ms || 45)} ms</span>
          </div>
        </td>
        <td>${flag} ${node.country || '🌍'}</td>
        <td style="color:#a5b4fc;">${node.host}:${node.port}</td>
        <td style="color:#e2e8f0;">${escapeHtml(node.tag || 'Server')}</td>
        <td>
          <button class="action-btn" onclick="copyNode('${escapeHtml(node.raw)}')">Копировать</button>
        </td>
      `;
      tbody.appendChild(tr);
    });
    document.getElementById('nodesCountDesc').innerText = `Найдено ${nodes.length} активных узлов с низкой задержкой`;
  }

  function getFlag(code) {
    const map = {
      'NL': '🇳🇱', 'DE': '🇩🇪', 'US': '🇺🇸', 'FR': '🇫🇷', 'SE': '🇸🇪',
      'GB': '🇬🇧', 'FI': '🇫🇮', 'TR': '🇹🇷', 'SG': '🇸🇬', 'JP': '🇯🇵',
      'KR': '🇰🇷', 'RU': '🇷🇺', 'PL': '🇵🇱', 'AT': '🇦🇹', 'RO': '🇷🇴'
    };
    return map[code] || '🌍';
  }

  function escapeHtml(text) {
    return text.replace(/'/g, "\\'").replace(/"/g, '&quot;');
  }

  function filterProto(proto) {
    if (proto === 'all') {
      renderTable(allWorkingNodes);
    } else {
      const filtered = allWorkingNodes.filter(n => n.proto.toLowerCase() === proto.toLowerCase());
      renderTable(filtered);
    }
  }

  async function runAnalysis() {
    const url = document.getElementById('targetUrl').value.trim();
    if (!url) return;

    const btn = document.getElementById('analyzeBtn');
    btn.disabled = true;
    btn.innerHTML = 'Проверка...';

    try {
      const resp = await fetch('/api/analyze?url=' + encodeURIComponent(url));
      const data = await resp.json();

      const diagBox = document.getElementById('diagBox');
      diagBox.style.display = 'block';

      if (data.diag.status === 'EXPIRED_OR_LIMITED') {
        diagBox.className = 'diag-box error';
        document.getElementById('diagStatusBadge').innerText = 'ЛИМИТ / ОШИБКА';
        document.getElementById('diagStatusBadge').style.background = 'rgba(255, 51, 102, 0.2)';
        document.getElementById('diagStatusBadge').style.color = 'var(--accent-red)';
      } else if (data.diag.status === 'ACTIVE') {
        diagBox.className = 'diag-box success';
        document.getElementById('diagStatusBadge').innerText = 'АКТИВНА';
      } else {
        diagBox.className = 'diag-box';
        document.getElementById('diagStatusBadge').innerText = data.diag.status;
      }

      document.getElementById('diagDomain').innerText = data.diag.domain || 'N/A';
      document.getElementById('diagBot').innerText = data.diag.bot_name || 'N/A';
      document.getElementById('diagWorkingCount').innerText = data.diag.real_nodes_count;
      document.getElementById('diagDummyCount').innerText = data.diag.dummy_nodes_count;

      const errDiv = document.getElementById('diagErrors');
      if (data.diag.error_messages && data.diag.error_messages.length > 0) {
        errDiv.innerHTML = '<b>Сообщения сервиса:</b><br>' + data.diag.error_messages.map(m => '• ' + m).join('<br>');
      } else {
        errDiv.innerHTML = '';
      }

      // Populate working nodes
      allWorkingNodes = data.working_nodes || [];
      currentBase64Sub = data.base64_sub || '';
      renderTable(allWorkingNodes);

      // Set subscription URL box
      const origin = window.location.origin;
      document.getElementById('subUrl').innerText = origin + '/sub';

    } catch (err) {
      console.error(err);
      alert('Ошибка при выполнении запроса к API');
    } finally {
      btn.disabled = false;
      btn.innerHTML = `<svg width="18" height="18" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg> Найти рабочие`;
    }
  }

  // Initial load
  window.addEventListener('DOMContentLoaded', () => {
    runAnalysis();
  });
</script>

</body>
</html>
"""


class SubRequestHandler(BaseHTTPRequestHandler):
    """HTTP обработчик для веб-панели и точки отдачи подписки."""

    def log_message(self, format, *args):
        # Concise logging
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = dict(urllib.parse.parse_qsl(parsed.query))

        # 1. Main Dashboard
        if path == "/" or path == "/index.html":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(HTML_PAGE.encode("utf-8"))
            return

        # 2. Subscription endpoint (Base64) for V2RayN, Happ, Hiddify, Streisand, etc.
        elif path == "/sub" or path == "/sub/":
            finder = WorkingSubscriptionFinder()
            candidates = finder.collect_candidates()
            tested = finder.test_nodes(candidates, max_workers=15, skip_ping=False)
            raw_lines = [n["raw"] for n in tested[:30]]
            b64_sub = encode_base64_subscription(raw_lines)

            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Profile-Update-Interval", "1")
            self.send_header("Subscription-Userinfo", "upload=1024; download=2048; total=1073741824000; expire=2546249531")
            self.send_header("Profile-Title", "base64:8J+GkyBBY3RpdmUgVlBOIFN1YnNjcmlwdGlvbg==")
            self.end_headers()
            self.wfile.write(b64_sub.encode("utf-8"))
            return

        # 3. Raw plain text subscription endpoint
        elif path == "/sub/raw" or path == "/sub.txt":
            finder = WorkingSubscriptionFinder()
            candidates = finder.collect_candidates()
            tested = finder.test_nodes(candidates, max_workers=15, skip_ping=False)
            raw_lines = [n["raw"] for n in tested[:30]]
            content = "\n".join(raw_lines) + "\n"

            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content.encode("utf-8"))
            return

        # 4. JSON API: /api/analyze
        elif path == "/api/analyze":
            target_url = query.get("url", "https://myvpnkey.com/sub/sub_b44503f8936a8be5c1567f4470c2dfc6")
            analyzer = SubscriptionAnalyzer(target_url)
            diag = analyzer.run()

            finder = WorkingSubscriptionFinder()
            candidates = finder.collect_candidates()
            tested = finder.test_nodes(candidates, max_workers=20, skip_ping=False)
            display_nodes = tested[:25]

            raw_lines = [n["raw"] for n in display_nodes]
            b64_sub = encode_base64_subscription(raw_lines)

            resp_data = {
                "diag": diag,
                "working_nodes": display_nodes,
                "base64_sub": b64_sub
            }

            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps(resp_data, ensure_ascii=False).encode("utf-8"))
            return

        # 404
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not Found")


def run_server(port: int = 8080):
    server_address = ("0.0.0.0", port)
    httpd = HTTPServer(server_address, SubRequestHandler)
    print(f"[*] Сервер подписки запущен на http://0.0.0.0:{port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[*] Остановка сервера...")
        httpd.server_close()


if __name__ == "__main__":
    run_server(PORT)
