#!/bin/bash

# --- RENK TANIMLAMALARI ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- FONKSIYONLAR ---
get_server_ip() { curl -s ifconfig.me; }

logo() {
    clear
    echo -e "${CYAN}"
    echo "███████╗████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗"
    echo "██╔════╝╚══██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║"
    echo "███████╗   ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║"
    echo "╚════██║   ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║"
    echo "███████║   ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗"
    echo "╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝"
    echo -e "${YELLOW}       VPN YONETIM PANELİ - KURULUM SIHIRBAZI v2.1"
    echo -e "${NC}------------------------------------------------------"
}

install_panel() {
    echo -e "${GREEN}[+] Kurulum Başlatılıyor...${NC}"
    
    # 1. TEMIZLIK & YEDEK
    if [ -d "/root/stunnel-panel" ]; then
        echo -e "${YELLOW}[!] Eski kurulum tespit edildi. Yedek alınıyor...${NC}"
        cp /root/stunnel-panel/users.json /root/users_backup_$(date +%F_%T).json 2>/dev/null
        systemctl stop stunnel-panel
        rm -rf /root/stunnel-panel
    fi

    # 2. PAKETLER
    echo -e "${BLUE}[INFO] Gerekli paketler yükleniyor...${NC}"
    apt update -y > /dev/null 2>&1
    apt install -y python3 python3-pip stunnel4 curl openssl shellinabox > /dev/null 2>&1
    pip3 install flask > /dev/null 2>&1

    # 3. KLASORLER & SERTIFIKA
    mkdir -p /root/stunnel-panel/templates
    
    if [ -f "/root/users_backup_*.json" ]; then
         LATEST_BACKUP=$(ls -t /root/users_backup_*.json | head -1)
         cp "$LATEST_BACKUP" /root/stunnel-panel/users.json
         echo -e "${GREEN}[+] Eski kullanıcı veritabanı geri yüklendi.${NC}"
    else
         touch /root/stunnel-panel/users.json
    fi

    if [ ! -f /etc/stunnel/stunnel.pem ]; then
        echo -e "${BLUE}[INFO] SSL Sertifikası oluşturuluyor...${NC}"
        openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=VPN/CN=VPNServer" \
        -keyout /etc/stunnel/stunnel.pem -out /etc/stunnel/stunnel.pem > /dev/null 2>&1
        chmod 600 /etc/stunnel/stunnel.pem
    fi

    cat << 'EOF' > /etc/stunnel/stunnel.conf
pid = /var/run/stunnel.pid
cert = /etc/stunnel/stunnel.pem
[dropbear-ssh]
accept = 443
connect = 127.0.0.1:22
EOF
    systemctl restart stunnel4

    # 4. PYTHON BACKEND (APP.PY)
    SERVER_IP=$(get_server_ip)
    
    cat << EOF > /root/stunnel-panel/app.py
from flask import Flask, render_template, request, redirect, url_for, session
import subprocess, os, json, pwd, shutil
from datetime import datetime, timedelta

app = Flask(__name__)
app.secret_key = "ultimate_setup_key_v2"
app.permanent_session_lifetime = timedelta(minutes=5)

DB_FILE = "/root/stunnel-panel/users.json"
ADMIN_USER = "admin"
ADMIN_PASS = "admin"
SERVER_IP = "${SERVER_IP}"

def get_online_count():
    try:
        cmd = "ps -eo user,comm | grep sshd | grep -v root | sort | uniq | wc -l"
        return subprocess.check_output(cmd, shell=True).decode().strip() or "0"
    except: return "0"

def get_system_stats():
    try:
        with open("/proc/loadavg", "r") as f: load = float(f.read().split()[0])
        cpu = min(int(load * 100), 100)
        mem = {}
        with open("/proc/meminfo", "r") as f:
            for line in f:
                p = line.split(':')
                if len(p) == 2: mem[p[0].strip()] = int(p[1].strip().split()[0])
        total = mem.get('MemTotal', 1)
        avail = mem.get('MemAvailable', mem.get('MemFree', 0))
        ram = int(((total - avail) / total) * 100)
        return cpu, ram
    except: return 0, 0

def load_db():
    if not os.path.exists(DB_FILE): return {}
    try:
        with open(DB_FILE, 'r') as f: return json.load(f)
    except: return {}

def save_db(data):
    with open(DB_FILE, 'w') as f: json.dump(data, f, indent=4)

def sys_cmd(cmd):
    subprocess.run(cmd, shell=True, stderr=subprocess.DEVNULL)

def ensure_iptables(username):
    try:
        uid = pwd.getpwnam(username).pw_uid
        tag = f"vpn_{username}"
        check = f"iptables -nL OUTPUT | grep '{tag}'"
        if subprocess.call(check, shell=True) != 0:
            sys_cmd(f"iptables -I OUTPUT -m owner --uid-owner {uid} -m comment --comment '{tag}' -j ACCEPT")
    except: pass

def get_used_bytes(username):
    try:
        tag = f"vpn_{username}"
        cmd = f"iptables -nvx -L OUTPUT | grep '{tag}' | awk '{{print \$2}}'"
        out = subprocess.check_output(cmd, shell=True).decode().strip()
        return int(out) if out else 0
    except: return 0

def reset_usage(username):
    try:
        uid = pwd.getpwnam(username).pw_uid
        tag = f"vpn_{username}"
        sys_cmd(f"iptables -D OUTPUT -m owner --uid-owner {uid} -m comment --comment '{tag}' -j ACCEPT")
        ensure_iptables(username)
    except: pass

def format_bytes(size):
    power = 2**10; n = 0; labels = {0:'', 1:'KB', 2:'MB', 3:'GB', 4:'TB'}
    while size > power: size /= power; n += 1
    return f"{size:.2f} {labels[n]}"

def manage_user(username, password, action, new_username=None):
    if action == "add":
        sys_cmd(f"userdel -r {username}")
        sys_cmd(f"useradd -M -s /bin/false {username}")
        p = subprocess.Popen(['chpasswd'], stdin=subprocess.PIPE)
        p.communicate(input=f'{username}:{password}'.encode())
        ensure_iptables(username)
    elif action == "rename":
        reset_usage(username)
        sys_cmd(f"pkill -u {username}")
        sys_cmd(f"usermod -l {new_username} {username}")
        p = subprocess.Popen(['chpasswd'], stdin=subprocess.PIPE)
        p.communicate(input=f'{new_username}:{password}'.encode())
        ensure_iptables(new_username)
    elif action == "del":
        try:
            uid = pwd.getpwnam(username).pw_uid
            tag = f"vpn_{username}"
            sys_cmd(f"iptables -D OUTPUT -m owner --uid-owner {uid} -m comment --comment '{tag}' -j ACCEPT")
        except: pass
        sys_cmd(f"userdel -r {username}")
    elif action == "lock": sys_cmd(f"passwd -l {username}")
    elif action == "unlock": sys_cmd(f"passwd -u {username}")

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        if request.form['username'] == ADMIN_USER and request.form['password'] == ADMIN_PASS:
            session['logged_in'] = True; session.permanent = True
            return redirect(url_for('index'))
        return render_template('login.html', error="Hatalı Giriş")
    return render_template('login.html')

@app.route('/logout')
def logout(): session.clear(); return redirect(url_for('login'))

@app.route('/')
def index():
    if not session.get('logged_in'): return redirect(url_for('login'))
    users = load_db()
    today = datetime.now().strftime("%Y-%m-%d")
    cpu, ram = get_system_stats()
    online_count = get_online_count()
    
    for u, data in users.items():
        ensure_iptables(u)
        used = get_used_bytes(u)
        limit_gb = int(data.get('quota_limit', 0))
        limit_bytes = limit_gb * 1024 * 1024 * 1024
        data['used_pretty'] = format_bytes(used)
        if limit_gb > 0:
            rem = max(0, limit_bytes - used)
            if rem == 0 and data['status'] == 'active':
                data['status'] = 'quota_full'; manage_user(u, "", "lock"); save_db(users)
            data['remaining_pretty'] = format_bytes(rem)
            data['percent'] = min(100, int((used / limit_bytes) * 100))
        else: data['remaining_pretty'] = "∞ Sınırsız"; data['percent'] = 0
        if data['expiry'] < today and data['status'] == 'active':
            data['status'] = 'expired'; manage_user(u, "", "lock"); save_db(users)

    return render_template('dashboard.html', users=users, cpu=cpu, ram=ram, online_count=online_count, ip=SERVER_IP)

@app.route('/add', methods=['POST'])
def add():
    if not session.get('logged_in'): return redirect(url_for('login'))
    u, p, d, q = request.form['u'], request.form['p'], int(request.form['d']), int(request.form['q'])
    exp = (datetime.now() + timedelta(days=d)).strftime("%Y-%m-%d")
    users = load_db()
    if u in users: return redirect(url_for('index'))
    users[u] = {"password": p, "expiry": exp, "quota_limit": q, "status": "active"}
    save_db(users); manage_user(u, p, "add")
    return redirect(url_for('index'))

@app.route('/edit', methods=['POST'])
def edit():
    if not session.get('logged_in'): return redirect(url_for('login'))
    old_u, new_u = request.form['old_u'], request.form['new_u']
    new_p, new_q, new_date = request.form['new_p'], int(request.form['new_q']), request.form['new_date']
    reset_q = 'reset_quota' in request.form
    users = load_db()
    user_data = users[old_u]
    user_data['password'] = new_p; user_data['quota_limit'] = new_q; user_data['expiry'] = new_date
    today = datetime.now().strftime("%Y-%m-%d")
    if new_date >= today and user_data['status'] == 'expired':
        user_data['status'] = 'active'; manage_user(old_u, new_p, "unlock")
    if old_u != new_u:
        manage_user(old_u, new_p, "rename", new_username=new_u)
        users[new_u] = user_data; del users[old_u]
        if reset_q: reset_usage(new_u)
    else:
        p = subprocess.Popen(['chpasswd'], stdin=subprocess.PIPE)
        p.communicate(input=f'{old_u}:{new_p}'.encode())
        if reset_q: reset_usage(old_u)
    save_db(users)
    return redirect(url_for('index'))

@app.route('/del/<u>')
def delete(u):
    if not session.get('logged_in'): return redirect(url_for('login'))
    users = load_db()
    if u in users: manage_user(u, "", "del"); del users[u]; save_db(users)
    return redirect(url_for('index'))

if __name__ == '__main__': app.run(host='0.0.0.0', port=5000)
EOF

    # 5. LOGIN HTML (ANIMASYONLU)
    cat << 'EOF' > /root/stunnel-panel/templates/login.html
<!DOCTYPE html><html lang="tr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>Panel Girişi</title><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet"><link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css"><style>body{margin:0;padding:0;height:100vh;font-family:'Segoe UI',sans-serif;overflow:hidden;display:flex;align-items:center;justify-content:center;background:#000}.bg-image{position:fixed;top:0;left:0;width:100%;height:100%;background:linear-gradient(rgba(0,0,0,0.3),rgba(0,0,0,0.5)),url('https://images.unsplash.com/photo-1590074258688-6a24340a4968?q=80&w=2000&auto=format&fit=crop');background-size:cover;background-position:center;z-index:-2;animation:breathe 25s infinite alternate}@keyframes breathe{0%{transform:scale(1)}100%{transform:scale(1.15)}}.particles{position:fixed;top:0;left:0;width:100%;height:100%;z-index:-1;pointer-events:none}.particles li{position:absolute;display:block;list-style:none;width:20px;height:20px;background:rgba(255,255,255,0.15);animation:floatUp 25s linear infinite;bottom:-150px;border-radius:4px}.particles li:nth-child(1){left:25%;width:80px;height:80px;animation-delay:0s}.particles li:nth-child(2){left:10%;width:20px;height:20px;animation-delay:2s;animation-duration:12s}.particles li:nth-child(4){left:40%;background:rgba(227,10,23,0.1)}@keyframes floatUp{0%{transform:translateY(0) rotate(0deg);opacity:1}100%{transform:translateY(-1000px) rotate(720deg);opacity:0}}.login-card{background:rgba(20,20,20,0.65);backdrop-filter:blur(15px);-webkit-backdrop-filter:blur(15px);border:1px solid rgba(255,255,255,0.15);border-radius:20px;padding:3rem 2.5rem;width:100%;max-width:400px;box-shadow:0 25px 50px -12px rgba(0,0,0,0.8);text-align:center;z-index:10}.logo-area{font-size:4rem;color:#e30a17;margin-bottom:1rem;text-shadow:0 0 20px rgba(227,10,23,0.6)}.panel-title{color:#fff;font-weight:700;letter-spacing:2px;margin-bottom:2rem;text-transform:uppercase;font-size:1.5rem}.form-control{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);color:#fff;padding:12px 20px;border-radius:10px;transition:all 0.3s ease}.form-control:focus{background:rgba(255,255,255,0.15);border-color:#e30a17;box-shadow:0 0 15px rgba(227,10,23,0.3);color:#fff}.form-control::placeholder{color:#bbb}.input-group-text{background:rgba(255,255,255,0.05);border:1px solid rgba(255,255,255,0.1);border-right:none;color:#e30a17}.btn-login{background:#e30a17;color:white;border:none;padding:12px;border-radius:10px;font-weight:bold;font-size:1.1rem;letter-spacing:1px;transition:all 0.3s;box-shadow:0 4px 15px rgba(227,10,23,0.4)}.btn-login:hover{background:#ff1f2d;transform:translateY(-2px);box-shadow:0 6px 20px rgba(227,10,23,0.6);color:#fff}.footer-text{margin-top:20px;color:rgba(255,255,255,0.5);font-size:0.8rem}</style></head><body><div class="bg-image"></div><ul class="particles"><li></li><li></li><li></li><li></li><li></li></ul><div class="login-card"><div class="logo-area"><i class="fas fa-star-and-crescent"></i></div><div class="panel-title">Yönetim Paneli</div>{% if error %}<div class="alert alert-danger py-2" style="background:rgba(220,53,69,0.2);border:1px solid #dc3545;color:#ff878d"><i class="fas fa-exclamation-circle"></i> {{error}}</div>{% endif %}<form method="POST"><div class="mb-3 input-group"><span class="input-group-text"><i class="fas fa-user"></i></span><input type="text" name="username" class="form-control" placeholder="Yönetici Adı" required></div><div class="mb-4 input-group"><span class="input-group-text"><i class="fas fa-lock"></i></span><input type="password" name="password" class="form-control" placeholder="Şifre" required></div><button type="submit" class="btn btn-login w-100">GİRİŞ YAP</button></form><div class="footer-text">&copy; 2025 Secure System</div></div></body></html>
EOF

    # 6. DASHBOARD HTML (FIXLI VE TAM)
    cat << 'EOF' > /root/stunnel-panel/templates/dashboard.html
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Panel</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
<style>
:root{--bg-color:#050505;--card-bg:#101010;--text-white:#ffffff;--text-bright:#e0e0e0;--accent:#00d2d3}
body{background-color:var(--bg-color);color:var(--text-white);font-family:'Segoe UI',sans-serif}
.card{background-color:var(--card-bg);border:1px solid #333;margin-bottom:1.5rem;box-shadow:0 0 15px rgba(0,0,0,0.5)}
.card-header{background:#1a1a1a;color:var(--accent);font-weight:bold;border-bottom:1px solid #333}
.stat-card{background:#1a1a1a;border:1px solid #333;padding:15px;border-radius:8px;text-align:center}
.stat-val{font-size:1.8rem;font-weight:bold;color:#fff}
.stat-label{font-size:0.8rem;color:#888;text-transform:uppercase;letter-spacing:1px}
.table{color:var(--text-bright)!important;margin-bottom:0}
.table th{background-color:#222!important;color:var(--accent)!important;border-bottom:2px solid #444!important}
.table td{background-color:transparent!important;border-bottom:1px solid #333!important;vertical-align:middle}
.user-text{color:#fff!important;font-weight:bold;font-size:1.1rem}
.pass-text{color:#ccc!important;font-family:monospace}
.quota-text{color:#e0e0e0!important;font-size:0.9rem}
.date-text{color:#ffffff!important;font-weight:500}
.form-control{background-color:#222;border:1px solid #444;color:#fff}
.form-control:focus{background-color:#222;color:#fff;border-color:var(--accent);box-shadow:none}
.modal-content{background-color:#1a1a1a;color:#fff;border:1px solid #444}
.btn-close{filter:invert(1)}
</style>
</head>
<body>
<nav class="navbar navbar-dark bg-dark mb-4 border-bottom border-secondary">
<div class="container">
<span class="navbar-brand"><i class="fas fa-bolt text-info"></i> YÖNETİM PANELİ</span>
<div class="d-flex align-items-center gap-3">
<span class="text-muted small d-none d-md-block">{{ ip }}</span>
<a href="/logout" class="btn btn-outline-danger btn-sm fw-bold"><i class="fas fa-sign-out-alt"></i> ÇIKIŞ</a>
</div>
</div>
</nav>
<div class="container">
<div class="row mb-4 g-3">
<div class="col-4"><div class="stat-card" style="border-top:3px solid #00d2d3"><div class="stat-label">ONLINE</div><div class="stat-val">{{ online_count }}</div></div></div>
<div class="col-4"><div class="stat-card" style="border-top:3px solid #ff9f43"><div class="stat-label">CPU</div><div class="stat-val">%{{ cpu }}</div></div></div>
<div class="col-4"><div class="stat-card" style="border-top:3px solid #5f27cd"><div class="stat-label">RAM</div><div class="stat-val">%{{ ram }}</div></div></div>
</div>
<div class="card">
<div class="card-header"><i class="fas fa-user-plus"></i> Hızlı Ekle</div>
<div class="card-body">
<form action="/add" method="POST" class="row g-3">
<div class="col-md-3 col-6"><input name="u" class="form-control" placeholder="Kullanıcı Adı" required></div>
<div class="col-md-3 col-6"><input name="p" class="form-control" placeholder="Şifre" required></div>
<div class="col-md-2 col-6"><input type="number" name="d" class="form-control" value="30" placeholder="Gün"></div>
<div class="col-md-2 col-6"><input type="number" name="q" class="form-control" value="5" placeholder="GB"></div>
<div class="col-md-2 col-12"><button class="btn btn-primary w-100">EKLE</button></div>
</form>
</div>
</div>
<div class="card">
<div class="card-header">Kullanıcılar ({{ users|length }})</div>
<div class="table-responsive">
<table class="table table-hover">
<thead><tr><th>Hesap Bilgileri</th><th>Kota Durumu</th><th>Bitiş Tarihi</th><th>Durum</th><th class="text-end">İşlem</th></tr></thead>
<tbody>
{% for u, d in users.items() %}
<tr>
<td><div class="user-text">{{ u }}</div><div class="pass-text"><i class="fas fa-key"></i> {{ d.password }}</div></td>
<td style="min-width:150px">
<div class="d-flex justify-content-between quota-text"><span>{{ d.used_pretty }}</span><span>{{ d.remaining_pretty }}</span></div>
{% if d.quota_limit > 0 %}<div class="progress" style="height:5px;margin-top:5px;background:#333"><div class="progress-bar bg-info" style="width:{{ d.percent }}%"></div></div>{% endif %}
</td>
<td class="date-text">{{ d.expiry }}</td>
<td>{% if d.status == 'active' %}<span class="badge bg-success">AKTİF</span>{% elif d.status == 'quota_full' %}<span class="badge bg-warning text-dark">DOLU</span>{% else %}<span class="badge bg-danger">BİTTİ</span>{% endif %}</td>
<td class="text-end">
<button class="btn btn-warning btn-sm" onclick="openEdit('{{u}}','{{d.password}}','{{d.quota_limit}}','{{d.expiry}}')"><i class="fas fa-pen"></i></button>
<a href="/del/{{ u }}" class="btn btn-danger btn-sm" onclick="return confirm('Silinsin mi?')"><i class="fas fa-trash"></i></a>
</td>
</tr>
{% else %}<tr><td colspan="5" class="text-center py-4 text-muted">Liste Boş</td></tr>{% endfor %}
</tbody>
</table>
</div>
</div>
</div>
<div class="modal fade" id="editModal" tabindex="-1">
<div class="modal-dialog modal-dialog-centered">
<div class="modal-content">
<div class="modal-header"><h5 class="modal-title">Düzenle</h5><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div>
<form action="/edit" method="POST">
<div class="modal-body">
<input type="hidden" name="old_u" id="modal_old_u">
<div class="mb-3"><label class="text-muted small">Kullanıcı Adı</label><input type="text" name="new_u" id="modal_new_u" class="form-control fw-bold"></div>
<div class="row g-2 mb-3">
<div class="col-6"><label class="text-muted small">Şifre</label><input type="text" name="new_p" id="modal_new_p" class="form-control"></div>
<div class="col-6"><label class="text-muted small">Kota (GB)</label><input type="number" name="new_q" id="modal_new_q" class="form-control"></div>
</div>
<div class="mb-3"><label class="text-muted small">Tarih</label><input type="date" name="new_date" id="modal_new_date" c
<div class="mb-3"><label class="text-muted small">Tarih</label><input type="date" name="new_date" id="modal_new_date" class="form-control"></div>
<div class="form-check border border-secondary p-3 rounded bg-dark">
<input class="form-check-input" type="checkbox" name="reset_quota" id="resetCheck">
<label class="form-check-label small" for="resetCheck">Kotayı Sıfırla</label>
</div>
</div>
<div class="modal-footer"><button class="btn btn-primary w-100">Kaydet</button></div>
</form>
</div>
</div>
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
function openEdit(u,p,q,d){
document.getElementById('modal_old_u').value=u;
document.getElementById('modal_new_u').value=u;
document.getElementById('modal_new_p').value=p;
document.getElementById('modal_new_q').value=q;
document.getElementById('modal_new_date').value=d;
document.getElementById('resetCheck').checked=false;
new bootstrap.Modal(document.getElementById('editModal')).show();
}
let inactivityTime=function(){
let time;
const timeoutDuration=300000;
window.onload=resetTimer;document.onmousemove=resetTimer;document.onkeypress=resetTimer;document.onclick=resetTimer;document.onscroll=resetTimer;
function logout(){window.location.href='/logout'}
function resetTimer(){clearTimeout(time);time=setTimeout(logout,timeoutDuration)}
};
inactivityTime();
</script>
</body>
</html>
EOF

    # 7. SERVIS
    cat << EOF > /etc/systemd/system/stunnel-panel.service
[Unit]
Description=Stunnel VPN Panel
After=network.target
[Service]
User=root
WorkingDirectory=/root/stunnel-panel
ExecStart=/usr/bin/python3 /root/stunnel-panel/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon
    systemctl daemon-reload
    systemctl enable stunnel-panel
    systemctl restart stunnel-panel
    
    echo -e "${GREEN}[OK] Kurulum Tamamlandı!${NC}"
    echo -e "${YELLOW}Panel: http://${SERVER_IP}:5000${NC}"
    echo -e "${YELLOW}Login: admin / admin${NC}"
}

remove_panel() {
    echo -e "${RED}[!] Kaldırılıyor...${NC}"
    systemctl stop stunnel-panel
    systemctl disable stunnel-panel
    rm -rf /etc/systemd/system/stunnel-panel.service
    systemctl daemon-reload
    rm -rf /root/stunnel-panel
    echo -e "${GREEN}[OK] Kaldırıldı.${NC}"
}

logo
echo "1) Paneli Kur / Güncelle"
echo "2) Paneli Kaldır"
echo "3) Çıkış"
read -p "Seçim: " choice
case $choice in
    1) install_panel ;;
    2) remove_panel ;;
    *) exit ;;
esac



