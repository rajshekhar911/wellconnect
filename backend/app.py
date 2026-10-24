import sqlite3
import uuid
import time

from flask import Flask, request, jsonify
from flask_socketio import SocketIO, emit
from flask_cors import CORS

app = Flask(__name__)
CORS(app, resources={r'/*': {'origins': '*'}})
socketio = SocketIO(app, cors_allowed_origins='*')

DB = 'chat.db'


def get_db():
    conn = sqlite3.connect(DB)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    conn.execute('CREATE TABLE IF NOT EXISTS users ('
                 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
                 'username TEXT, '
                 'category TEXT, '
                 'token TEXT, '
                 'sid TEXT, '
                 'online INTEGER DEFAULT 0)')
    conn.execute('CREATE TABLE IF NOT EXISTS messages ('
                 'id INTEGER PRIMARY KEY AUTOINCREMENT, '
                 'sender_id INTEGER, '
                 'receiver_id INTEGER, '
                 'text TEXT, '
                 'timestamp INTEGER)')
    conn.commit()
    conn.close()


init_db()


@app.route('/login', methods=['POST'])
def login():
    data = request.get_json(force=True, silent=True) or {}
    category = data.get('category')
    username = (data.get('username') or '').strip()

    if category not in ('A', 'B'):
        return jsonify({'error': 'Category must be A or B'}), 400
    if category == 'A' and not username:
        return jsonify({'error': 'Username required for category A'}), 400

    token = uuid.uuid4().hex
    conn = get_db()
    if category == 'B':
        username = 'Anon-' + uuid.uuid4().hex[:6]
        cur = conn.execute('INSERT INTO users (username, category, token) VALUES (?, ?, ?)',
                           (username, category, token))
        conn.commit()
        user_id = cur.lastrowid
    else:
        row = conn.execute('SELECT id FROM users WHERE username = ?', (username,)).fetchone()
        if row:
            user_id = row['id']
            conn.execute('UPDATE users SET token = ? WHERE id = ?', (token, user_id))
            conn.commit()
        else:
            cur = conn.execute('INSERT INTO users (username, category, token) VALUES (?, ?, ?)',
                               (username, category, token))
            conn.commit()
            user_id = cur.lastrowid
    conn.close()
    return jsonify({'token': token, 'user_id': user_id, 'username': username, 'category': category})


def current_user():
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE sid = ?', (request.sid,)).fetchone()
    conn.close()
    return user


def broadcast_users():
    conn = get_db()
    users = conn.execute('SELECT * FROM users WHERE online = 1').fetchall()
    conn.close()
    for me in users:
        visible = []
        for other in users:
            if other['id'] == me['id']:
                continue
            if me['category'] == 'B' and other['category'] == 'B':
                continue
            visible.append({'id': other['id'], 'username': other['username'],
                            'category': other['category']})
        socketio.emit('user_list', visible, to=me['sid'])


@socketio.on('connect')
def on_connect():
    token = request.args.get('token')
    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE token = ?', (token,)).fetchone()
    if not user:
        conn.close()
        return False
    conn.execute('UPDATE users SET sid = ?, online = 1 WHERE id = ?', (request.sid, user['id']))
    conn.commit()
    conn.close()
    broadcast_users()


@socketio.on('disconnect')
def on_disconnect():
    conn = get_db()
    conn.execute('UPDATE users SET sid = NULL, online = 0 WHERE sid = ?', (request.sid,))
    conn.commit()
    conn.close()
    broadcast_users()


@socketio.on('get_history')
def on_get_history(data):
    me = current_user()
    if not me:
        return
    other_id = data.get('user_id')
    conn = get_db()
    rows = conn.execute(
        'SELECT * FROM messages WHERE (sender_id = ? AND receiver_id = ?) '
        'OR (sender_id = ? AND receiver_id = ?) ORDER BY timestamp',
        (me['id'], other_id, other_id, me['id'])).fetchall()
    conn.close()
    emit('message_history', [dict(r) for r in rows])


@socketio.on('send_message')
def on_send_message(data):
    me = current_user()
    if not me:
        return
    other_id = data.get('to')
    text = (data.get('message') or '').strip()
    if not text:
        return
    conn = get_db()
    receiver = conn.execute('SELECT * FROM users WHERE id = ?', (other_id,)).fetchone()
    if not receiver or (me['category'] == 'B' and receiver['category'] == 'B'):
        conn.close()
        return
    ts = int(time.time())
    cur = conn.execute('INSERT INTO messages (sender_id, receiver_id, text, timestamp) '
                       'VALUES (?, ?, ?, ?)', (me['id'], other_id, text, ts))
    conn.commit()
    msg_id = cur.lastrowid
    conn.close()
    msg = {'id': msg_id, 'sender_id': me['id'], 'receiver_id': other_id,
           'text': text, 'timestamp': ts}
    emit('new_message', msg)
    if receiver['sid']:
        socketio.emit('new_message', msg, to=receiver['sid'])


if __name__ == '__main__':
    socketio.run(app, host='0.0.0.0', port=5000, debug=True)
