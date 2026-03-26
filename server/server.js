'use strict';

const http   = require('http');
const { Server } = require('socket.io');

const server = http.createServer();
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET', 'POST'] },
});

/**
 * Each entry: { socket, playerName }
 * @type {Array<{socket: import('socket.io').Socket, playerName: string}>}
 */
const waitingQueue = [];

/**
 * roomId → { players: Set<socketId>, hostId: string, readyCount: number }
 * @type {Map<string, {players: Set<string>, hostId: string, readyCount: number}>}
 */
const rooms = new Map();

function findRoomBySocket(socketId) {
  for (const [roomId, room] of rooms) {
    if (room.players.has(socketId)) return { roomId, room };
  }
  return null;
}

io.on('connection', (socket) => {
  console.log(`[+] ${socket.id} connected  (total: ${io.engine.clientsCount})`);

  // ── Matchmaking ────────────────────────────────────────────────────────────

  socket.on('find_match', ({ player_name }) => {
    if (waitingQueue.length > 0) {
      const opponent = waitingQueue.shift();
      const roomId   = `room_${Date.now()}_${Math.floor(Math.random() * 9999)}`;
      const room     = {
        players:    new Set([socket.id, opponent.socket.id]),
        hostId:     opponent.socket.id,
        readyCount: 0,
      };
      rooms.set(roomId, room);
      socket.join(roomId);
      opponent.socket.join(roomId);

      socket.emit('match_found', {
        room_id:      roomId,
        partner_name: opponent.playerName,
        is_host:      false,
      });
      opponent.socket.emit('match_found', {
        room_id:      roomId,
        partner_name: player_name,
        is_host:      true,
      });
      console.log(`[room] ${roomId}: host=${opponent.socket.id}  join=${socket.id}`);
    } else {
      waitingQueue.push({ socket, playerName: player_name });
      socket.emit('searching', {});
      console.log(`[queue] ${socket.id} (${player_name}) waiting – queue: ${waitingQueue.length}`);
    }
  });

  socket.on('cancel_search', () => {
    const idx = waitingQueue.findIndex(e => e.socket.id === socket.id);
    if (idx !== -1) waitingQueue.splice(idx, 1);
  });

  socket.on('player_ready', ({ room_id }) => {
    const room = rooms.get(room_id);
    if (!room) return;
    room.readyCount += 1;
    socket.to(room_id).emit('partner_ready', {});
    if (room.readyCount >= 2) {
      io.to(room_id).emit('game_start', {});
      console.log(`[room] ${room_id}: game started`);
    }
  });

  // ── In-game relay (no game logic on the server) ────────────────────────────

  // Real-time player position/animation
  socket.on('player_state', (data) => {
    socket.to(data.room_id).emit('remote_player_state', data);
  });

  // Visual bullet relay (partner sees bullets being fired)
  socket.on('bullet_fired', (data) => {
    socket.to(data.room_id).emit('remote_bullet_fired', data);
  });

  // Partner died → tell other player
  socket.on('player_died', ({ room_id }) => {
    socket.to(room_id).emit('partner_died', {});
    console.log(`[room] ${room_id}: a player died`);
  });

  // ── Disconnect ────────────────────────────────────────────────────────────

  socket.on('disconnect', () => {
    console.log(`[-] ${socket.id} disconnected`);
    // Remove from waiting queue
    const qIdx = waitingQueue.findIndex(e => e.socket.id === socket.id);
    if (qIdx !== -1) waitingQueue.splice(qIdx, 1);
    // Notify room partner
    const result = findRoomBySocket(socket.id);
    if (result) {
      socket.to(result.roomId).emit('partner_disconnected', {});
      rooms.delete(result.roomId);
      console.log(`[room] ${result.roomId}: closed (partner disconnected)`);
    }
  });
});

const PORT = parseInt(process.env.PORT || '3000', 10);
server.listen(PORT, () => {
  console.log(`Resistance co-op server listening on port ${PORT}`);
  console.log(`Update SERVER_URL in scripts/network_manager.gd to point here.`);
});
