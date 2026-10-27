import sqlite3
import uuid
import time
import random
import contextlib
from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit, join_room, leave_room
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash

app = Flask(__name__)
app.config['SECRET_KEY'] = 'wellconnect-secret-key-prod-2025'
CORS(app, resources={r'/*': {'origins': '*'}})
socketio = SocketIO(app, cors_allowed_origins='*', ping_timeout=20, ping_interval=10)

DB = 'chat.db'

ADJECTIVES = [
    'Calm', 'Serene', 'Kind', 'Wise', 'Bright', 'Gentle', 'Quiet', 'Patient',
    'Brave', 'Mindful', 'Peaceful', 'Warm', 'Swift', 'Mystic', 'Hopeful'
]
NOUNS = [
    'River', 'Sparrow', 'Forest', 'Beacon', 'Harbor', 'Panda', 'Falcon',
    'Meadow', 'Horizon', 'Breeze', 'Voyager', 'Haven', 'Willow', 'Summit', 'Otter'
]


@contextlib.contextmanager
def db_conn():
    conn = sqlite3.connect(DB, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        yield conn
    finally:
        conn.close()


def init_db():
    with db_conn() as conn:
        conn.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                display_name TEXT,
                category TEXT NOT NULL CHECK(category IN ('A', 'B')),
                password_hash TEXT,
                recovery_key TEXT,
                token TEXT,
                sid TEXT,
                online INTEGER DEFAULT 0,
                last_seen INTEGER DEFAULT 0,
                created_at INTEGER DEFAULT 0
            )
        ''')

        # Auto-migrate columns if database already existed
        cur = conn.execute("PRAGMA table_info(users)")
        cols = [r['name'] for r in cur.fetchall()]
        if 'display_name' not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN display_name TEXT")
        if 'password_hash' not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN password_hash TEXT")
        if 'recovery_key' not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN recovery_key TEXT")
        if 'last_seen' not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN last_seen INTEGER DEFAULT 0")
        if 'created_at' not in cols:
            conn.execute("ALTER TABLE users ADD COLUMN created_at INTEGER DEFAULT 0")

        conn.execute('''
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                client_id TEXT,
                sender_id INTEGER NOT NULL,
                receiver_id INTEGER NOT NULL,
                text TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                status TEXT DEFAULT 'sent',
                deleted INTEGER DEFAULT 0,
                FOREIGN KEY(sender_id) REFERENCES users(id),
                FOREIGN KEY(receiver_id) REFERENCES users(id)
            )
        ''')

        cur = conn.execute("PRAGMA table_info(messages)")
        m_cols = [r['name'] for r in cur.fetchall()]
        if 'client_id' not in m_cols:
            conn.execute("ALTER TABLE messages ADD COLUMN client_id TEXT")
        if 'status' not in m_cols:
            conn.execute("ALTER TABLE messages ADD COLUMN status TEXT DEFAULT 'sent'")
        if 'deleted' not in m_cols:
            conn.execute("ALTER TABLE messages ADD COLUMN deleted INTEGER DEFAULT 0")

        conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_pair ON messages(sender_id, receiver_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_messages_ts ON messages(timestamp)")
        conn.commit()


init_db()


def generate_anonymous_name():
    for _ in range(50):
        name = f"{random.choice(ADJECTIVES)}{random.choice(NOUNS)}{random.randint(100, 999)}"
        with db_conn() as conn:
            row = conn.execute("SELECT id FROM users WHERE username = ?", (name,)).fetchone()
            if not row:
                return name
    return f"Anon-{uuid.uuid4().hex[:6]}"


# -------------------------------------------------------------
# REST API ENDPOINTS
# -------------------------------------------------------------

@app.route('/api/register', methods=['POST'])
def register_known():
    data = request.get_json(force=True, silent=True) or {}
    username = (data.get('username') or '').strip()
    password = (data.get('password') or '').strip()
    display_name = (data.get('display_name') or username).strip()

    if not username or len(username) < 3:
        return jsonify({'error': 'Username must be at least 3 characters'}), 400
    if not password or len(password) < 4:
        return jsonify({'error': 'Password must be at least 4 characters'}), 400

    now = int(time.time())
    token = uuid.uuid4().hex
    pwd_hash = generate_password_hash(password)

    with db_conn() as conn:
        existing = conn.execute("SELECT id FROM users WHERE username = ?", (username,)).fetchone()
        if existing:
            return jsonify({'error': 'Username already taken'}), 409

        cur = conn.execute(
            '''INSERT INTO users (username, display_name, category, password_hash, token, created_at, last_seen)
               VALUES (?, ?, 'A', ?, ?, ?, ?)''',
            (username, display_name, pwd_hash, token, now, now)
        )
        conn.commit()
        user_id = cur.lastrowid

    return jsonify({
        'token': token,
        'user_id': user_id,
        'username': username,
        'display_name': display_name,
        'category': 'A'
    })


@app.route('/api/login', methods=['POST'])
def login_known():
    data = request.get_json(force=True, silent=True) or {}
    username = (data.get('username') or '').strip()
    password = (data.get('password') or '').strip()

    if not username or not password:
        return jsonify({'error': 'Username and password required'}), 400

    with db_conn() as conn:
        user = conn.execute("SELECT * FROM users WHERE username = ? AND category = 'A'", (username,)).fetchone()
        if not user or not user['password_hash'] or not check_password_hash(user['password_hash'], password):
            return jsonify({'error': 'Invalid username or password'}), 401

        token = uuid.uuid4().hex
        conn.execute("UPDATE users SET token = ? WHERE id = ?", (token, user['id']))
        conn.commit()

        return jsonify({
            'token': token,
            'user_id': user['id'],
            'username': user['username'],
            'display_name': user['display_name'] or user['username'],
            'category': 'A'
        })


@app.route('/api/register/anonymous', methods=['POST'])
def register_anonymous():
    now = int(time.time())
    username = generate_anonymous_name()
    recovery_key = f"anon_{uuid.uuid4().hex[:12]}"
    token = uuid.uuid4().hex

    with db_conn() as conn:
        cur = conn.execute(
            '''INSERT INTO users (username, display_name, category, recovery_key, token, created_at, last_seen)
               VALUES (?, ?, 'B', ?, ?, ?, ?)''',
            (username, username, recovery_key, token, now, now)
        )
        conn.commit()
        user_id = cur.lastrowid

    return jsonify({
        'token': token,
        'user_id': user_id,
        'username': username,
        'display_name': username,
        'category': 'B',
        'recovery_key': recovery_key
    })


@app.route('/api/login/anonymous', methods=['POST'])
def login_anonymous():
    data = request.get_json(force=True, silent=True) or {}
    recovery_key = (data.get('recovery_key') or '').strip()

    if not recovery_key:
        return jsonify({'error': 'Recovery key required'}), 400

    with db_conn() as conn:
        user = conn.execute("SELECT * FROM users WHERE recovery_key = ? AND category = 'B'", (recovery_key,)).fetchone()
        if not user:
            return jsonify({'error': 'No anonymous account found with this recovery key'}), 404

        token = uuid.uuid4().hex
        conn.execute("UPDATE users SET token = ? WHERE id = ?", (token, user['id']))
        conn.commit()

        return jsonify({
            'token': token,
            'user_id': user['id'],
            'username': user['username'],
            'display_name': user['display_name'] or user['username'],
            'category': 'B',
            'recovery_key': user['recovery_key']
        })


@app.route('/api/me', methods=['GET'])
def get_me():
    auth_header = request.headers.get('Authorization', '')
    token = auth_header.replace('Bearer ', '').strip() or request.args.get('token')

    if not token:
        return jsonify({'error': 'Unauthorized'}), 401

    with db_conn() as conn:
        user = conn.execute("SELECT * FROM users WHERE token = ?", (token,)).fetchone()
        if not user:
            return jsonify({'error': 'Session expired'}), 401

        return jsonify({
            'token': token,
            'user_id': user['id'],
            'username': user['username'],
            'display_name': user['display_name'] or user['username'],
            'category': user['category'],
            'recovery_key': user['recovery_key']
        })


# Legacy /login endpoint for backward compatibility
@app.route('/login', methods=['POST'])
def legacy_login():
    data = request.get_json(force=True, silent=True) or {}
    category = data.get('category')
    username = (data.get('username') or '').strip()

    if category == 'B':
        return register_anonymous()
    if category == 'A':
        if not username:
            return jsonify({'error': 'Username required'}), 400
        with db_conn() as conn:
            user = conn.execute("SELECT * FROM users WHERE username = ?", (username,)).fetchone()
            token = uuid.uuid4().hex
            now = int(time.time())
            if user:
                user_id = user['id']
                conn.execute("UPDATE users SET token = ? WHERE id = ?", (token, user_id))
            else:
                cur = conn.execute(
                    "INSERT INTO users (username, display_name, category, token, created_at, last_seen) VALUES (?, ?, 'A', ?, ?, ?)",
                    (username, username, token, now, now)
                )
                user_id = cur.lastrowid
            conn.commit()
            return jsonify({
                'token': token,
                'user_id': user_id,
                'username': username,
                'display_name': username,
                'category': 'A'
            })
    return jsonify({'error': 'Invalid category'}), 400


# -------------------------------------------------------------
# SOCKET.IO HANDLERS
# -------------------------------------------------------------

def get_user_by_sid(sid):
    with db_conn() as conn:
        return conn.execute("SELECT * FROM users WHERE sid = ?", (sid,)).fetchone()


def get_visible_users_for(me):
    with db_conn() as conn:
        all_users = conn.execute("SELECT * FROM users WHERE id != ?", (me['id'],)).fetchall()
        result = []
        for other in all_users:
            # Rule: Anonymous cannot see Anonymous
            if me['category'] == 'B' and other['category'] == 'B':
                continue

            # Fetch last message
            last_msg = conn.execute(
                '''SELECT id, text, timestamp, sender_id, status, deleted FROM messages
                   WHERE (sender_id = ? AND receiver_id = ?)
                      OR (sender_id = ? AND receiver_id = ?)
                   ORDER BY timestamp DESC, id DESC LIMIT 1''',
                (me['id'], other['id'], other['id'], me['id'])
            ).fetchone()

            # Fetch unread count
            unread_row = conn.execute(
                '''SELECT COUNT(*) as count FROM messages
                   WHERE sender_id = ? AND receiver_id = ? AND status != 'read' AND deleted = 0''',
                (other['id'], me['id'])
            ).fetchone()

            result.append({
                'id': other['id'],
                'username': other['username'],
                'display_name': other['display_name'] or other['username'],
                'category': other['category'],
                'online': bool(other['online']),
                'last_seen': other['last_seen'] or 0,
                'unread_count': unread_row['count'] if unread_row else 0,
                'last_message': dict(last_msg) if last_msg else None
            })

        # Sort: newest conversation first, then online status, then name
        result.sort(
            key=lambda u: (
                u['last_message']['timestamp'] if u['last_message'] else 0,
                1 if u['online'] else 0
            ),
            reverse=True
        )
        return result


def push_user_list_to(user_id):
    with db_conn() as conn:
        user = conn.execute("SELECT * FROM users WHERE id = ?", (user_id,)).fetchone()
    if user and user['online']:
        users = get_visible_users_for(user)
        socketio.emit('user_list', users, room=f"user_{user_id}")


def broadcast_presence():
    with db_conn() as conn:
        online_users = conn.execute("SELECT id FROM users WHERE online = 1").fetchall()
    for u in online_users:
        push_user_list_to(u['id'])


@socketio.on('connect')
def on_connect():
    token = request.args.get('token')
    if not token and hasattr(request, 'headers'):
        token = request.headers.get('token')

    if not token:
        return False

    with db_conn() as conn:
        user = conn.execute("SELECT * FROM users WHERE token = ?", (token,)).fetchone()
        if not user:
            return False

        conn.execute("UPDATE users SET sid = ?, online = 1, last_seen = ? WHERE id = ?",
                     (request.sid, int(time.time()), user['id']))

        # Mark all messages sent to this user as 'delivered' if currently 'sent'
        pending = conn.execute(
            "SELECT id, sender_id FROM messages WHERE receiver_id = ? AND status = 'sent'",
            (user['id'],)
        ).fetchall()

        if pending:
            conn.execute("UPDATE messages SET status = 'delivered' WHERE receiver_id = ? AND status = 'sent'",
                         (user['id'],))
            conn.commit()

            for p in pending:
                socketio.emit('message_status_update', {
                    'message_id': p['id'],
                    'status': 'delivered'
                }, room=f"user_{p['sender_id']}")
        else:
            conn.commit()

    join_room(f"user_{user['id']}")
    broadcast_presence()


@socketio.on('disconnect')
def on_disconnect():
    now = int(time.time())
    with db_conn() as conn:
        user = conn.execute("SELECT id FROM users WHERE sid = ?", (request.sid,)).fetchone()
        if user:
            conn.execute("UPDATE users SET sid = NULL, online = 0, last_seen = ? WHERE id = ?",
                         (now, user['id']))
            conn.commit()
            leave_room(f"user_{user['id']}")
    broadcast_presence()


@socketio.on('get_users')
def on_get_users():
    me = get_user_by_sid(request.sid)
    if not me:
        return
    users = get_visible_users_for(me)
    emit('user_list', users)


@socketio.on('get_history')
def on_get_history(data):
    me = get_user_by_sid(request.sid)
    if not me:
        return
    other_id = data.get('user_id')
    if not other_id:
        return

    with db_conn() as conn:
        # Mark all messages from other to me as read
        conn.execute(
            "UPDATE messages SET status = 'read' WHERE sender_id = ? AND receiver_id = ? AND status != 'read'",
            (other_id, me['id'])
        )
        conn.commit()

        rows = conn.execute(
            '''SELECT id, client_id, sender_id, receiver_id, text, timestamp, status, deleted
               FROM messages
               WHERE (sender_id = ? AND receiver_id = ?)
                  OR (sender_id = ? AND receiver_id = ?)
               ORDER BY timestamp ASC, id ASC''',
            (me['id'], other_id, other_id, me['id'])
        ).fetchall()

    # Inform other user that their messages were read
    socketio.emit('messages_read', {'by_user_id': me['id']}, room=f"user_{other_id}")

    emit('message_history', [dict(r) for r in rows])
    # Refresh unread badges for me
    push_user_list_to(me['id'])


@socketio.on('send_message')
def on_send_message(data):
    me = get_user_by_sid(request.sid)
    if not me:
        return

    other_id = data.get('to')
    text = (data.get('message') or '').strip()
    client_id = data.get('client_id') or uuid.uuid4().hex

    if not text or not other_id:
        return

    with db_conn() as conn:
        receiver = conn.execute("SELECT * FROM users WHERE id = ?", (other_id,)).fetchone()
        if not receiver:
            emit('error', {'message': 'Recipient not found'})
            return

        # Security check: Category B cannot talk to Category B
        if me['category'] == 'B' and receiver['category'] == 'B':
            emit('error', {'message': 'Anonymous users cannot message other anonymous users'})
            return

        now = int(time.time())
        status = 'delivered' if receiver['online'] else 'sent'

        cur = conn.execute(
            '''INSERT INTO messages (client_id, sender_id, receiver_id, text, timestamp, status, deleted)
               VALUES (?, ?, ?, ?, ?, ?, 0)''',
            (client_id, me['id'], other_id, text, now, status)
        )
        conn.commit()
        msg_id = cur.lastrowid

    msg_payload = {
        'id': msg_id,
        'client_id': client_id,
        'sender_id': me['id'],
        'receiver_id': other_id,
        'text': text,
        'timestamp': now,
        'status': status,
        'deleted': 0
    }

    # Emit to sender & receiver rooms
    socketio.emit('new_message', msg_payload, room=f"user_{me['id']}")
    socketio.emit('new_message', msg_payload, room=f"user_{other_id}")

    # Update conversation snippets on both sides
    push_user_list_to(me['id'])
    push_user_list_to(other_id)


@socketio.on('mark_read')
def on_mark_read(data):
    me = get_user_by_sid(request.sid)
    if not me:
        return
    sender_id = data.get('sender_id')
    if not sender_id:
        return

    with db_conn() as conn:
        conn.execute(
            "UPDATE messages SET status = 'read' WHERE sender_id = ? AND receiver_id = ? AND status != 'read'",
            (sender_id, me['id'])
        )
        conn.commit()

    socketio.emit('messages_read', {'by_user_id': me['id']}, room=f"user_{sender_id}")
    push_user_list_to(me['id'])


@socketio.on('typing')
def on_typing(data):
    me = get_user_by_sid(request.sid)
    if not me:
        return
    to_id = data.get('to')
    is_typing = bool(data.get('is_typing'))
    if to_id:
        socketio.emit('typing_status', {
            'user_id': me['id'],
            'is_typing': is_typing
        }, room=f"user_{to_id}")


@socketio.on('delete_message')
def on_delete_message(data):
    me = get_user_by_sid(request.sid)
    if not me:
        return
    msg_id = data.get('message_id')

    with db_conn() as conn:
        msg = conn.execute("SELECT * FROM messages WHERE id = ?", (msg_id,)).fetchone()
        if not msg or msg['sender_id'] != me['id']:
            return

        conn.execute(
            "UPDATE messages SET deleted = 1, text = 'This message was deleted' WHERE id = ?",
            (msg_id,)
        )
        conn.commit()

        receiver_id = msg['receiver_id']

    payload = {'message_id': msg_id, 'sender_id': me['id'], 'receiver_id': receiver_id}
    socketio.emit('message_deleted', payload, room=f"user_{me['id']}")
    socketio.emit('message_deleted', payload, room=f"user_{receiver_id}")

    push_user_list_to(me['id'])
    push_user_list_to(receiver_id)


@app.route('/')
def home():
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <title>WellConnect Server</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
                margin: 0;
                background: #f5f5f5;
            }

            .box {
                background: white;
                padding: 40px;
                border-radius: 15px;
                box-shadow: 0 4px 20px rgba(0,0,0,0.1);
                text-align: center;
            }

            .status {
                color: #16a34a;
                font-size: 20px;
                font-weight: bold;
            }

            .dot {
                display: inline-block;
                width: 12px;
                height: 12px;
                background: #16a34a;
                border-radius: 50%;
                margin-right: 8px;
            }
        </style>
    </head>
    <body>
        <div class="box">
            <h1>WellConnect Server</h1>
            <p class="status">
                <span class="dot"></span>
                Server is connected and running
            </p>
            <p>Flask + Socket.IO</p>
            <p>Port: 5000</p>
        </div>
    </body>
    </html>
    '''

if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)