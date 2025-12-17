/**
 * Social Tipping Chainhook Event Server
 * Handles events from Hiro Chainhooks for the Social Tipping Platform
 */

const express = require('express');
const cors = require('cors');
const Database = require('better-sqlite3');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3003;
const AUTH_TOKEN = process.env.AUTH_TOKEN || 'YOUR_AUTH_TOKEN';

const db = new Database('tipping_events.db');

// Create tables
db.exec(`
  CREATE TABLE IF NOT EXISTS creators (
    address TEXT PRIMARY KEY,
    creator_id INTEGER,
    username TEXT,
    bio TEXT,
    registered_at INTEGER,
    total_tips INTEGER DEFAULT 0,
    total_amount INTEGER DEFAULT 0,
    supporter_count INTEGER DEFAULT 0,
    content_count INTEGER DEFAULT 0,
    verified INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS tips (
    tip_id INTEGER PRIMARY KEY,
    tipper TEXT,
    creator TEXT,
    amount INTEGER,
    fee INTEGER,
    content_id INTEGER,
    has_message INTEGER,
    timestamp INTEGER,
    block_height INTEGER,
    tx_id TEXT
  );

  CREATE TABLE IF NOT EXISTS tippers (
    address TEXT PRIMARY KEY,
    total_tips INTEGER DEFAULT 0,
    total_amount INTEGER DEFAULT 0,
    creators_supported INTEGER DEFAULT 0,
    fees_paid INTEGER DEFAULT 0,
    first_tip INTEGER,
    last_tip INTEGER
  );

  CREATE TABLE IF NOT EXISTS content (
    content_id INTEGER PRIMARY KEY,
    creator TEXT,
    content_type TEXT,
    title TEXT,
    tips_count INTEGER DEFAULT 0,
    tips_amount INTEGER DEFAULT 0,
    created_at INTEGER
  );

  CREATE TABLE IF NOT EXISTS fees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tip_id INTEGER,
    amount INTEGER,
    timestamp INTEGER
  );

  CREATE TABLE IF NOT EXISTS daily_stats (
    date TEXT PRIMARY KEY,
    tips_count INTEGER DEFAULT 0,
    tips_volume INTEGER DEFAULT 0,
    fees_collected INTEGER DEFAULT 0,
    new_creators INTEGER DEFAULT 0,
    new_tippers INTEGER DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS leaderboard (
    creator TEXT PRIMARY KEY,
    total_earnings INTEGER DEFAULT 0,
    tip_count INTEGER DEFAULT 0,
    supporter_count INTEGER DEFAULT 0,
    rank INTEGER
  );
`);

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const authMiddleware = (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${AUTH_TOKEN}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
};

const extractEventData = (payload) => {
  const events = [];
  if (payload.apply && Array.isArray(payload.apply)) {
    for (const block of payload.apply) {
      const blockHeight = block.block_identifier?.index;
      if (block.transactions && Array.isArray(block.transactions)) {
        for (const tx of block.transactions) {
          const txId = tx.transaction_identifier?.hash;
          if (tx.metadata?.receipt?.events) {
            for (const event of tx.metadata.receipt.events) {
              if (event.type === 'SmartContractEvent' || event.type === 'print_event') {
                const printData = event.data?.value || event.contract_event?.value;
                if (printData) events.push({ data: printData, blockHeight, txId });
              }
            }
          }
        }
      }
    }
  }
  return events;
};

const updateDailyStats = (date, field, increment = 1) => {
  const existing = db.prepare('SELECT * FROM daily_stats WHERE date = ?').get(date);
  if (existing) {
    db.prepare(`UPDATE daily_stats SET ${field} = ${field} + ? WHERE date = ?`).run(increment, date);
  } else {
    db.prepare(`INSERT INTO daily_stats (date, ${field}) VALUES (?, ?)`).run(date, increment);
  }
};

const updateLeaderboard = () => {
  db.exec(`
    INSERT OR REPLACE INTO leaderboard (creator, total_earnings, tip_count, supporter_count, rank)
    SELECT address, total_amount, total_tips, supporter_count, 
           ROW_NUMBER() OVER (ORDER BY total_amount DESC) as rank
    FROM creators
    ORDER BY total_amount DESC
    LIMIT 100
  `);
};

const processEvent = (eventData, blockHeight, txId) => {
  const today = new Date().toISOString().split('T')[0];
  const timestamp = eventData.timestamp || Math.floor(Date.now() / 1000);

  switch (eventData.event) {
    case 'creator-registered':
      db.prepare(`INSERT OR REPLACE INTO creators (address, creator_id, username, registered_at) VALUES (?, ?, ?, ?)`)
        .run(eventData.creator, eventData['creator-id'], eventData.username, timestamp);
      updateDailyStats(today, 'new_creators');
      console.log(`👤 Creator registered: @${eventData.username}`);
      break;

    case 'tip-sent':
      db.prepare(`INSERT INTO tips (tip_id, tipper, creator, amount, fee, content_id, has_message, timestamp, block_height, tx_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
        .run(eventData['tip-id'], eventData.tipper, eventData.creator, eventData.amount, eventData.fee, eventData['content-id'], eventData['has-message'] ? 1 : 0, timestamp, blockHeight, txId);
      
      // Update creator
      db.prepare(`UPDATE creators SET total_tips = total_tips + 1, total_amount = total_amount + ? WHERE address = ?`)
        .run(eventData.amount, eventData.creator);
      
      // Update tipper
      const tipper = db.prepare('SELECT * FROM tippers WHERE address = ?').get(eventData.tipper);
      if (tipper) {
        db.prepare(`UPDATE tippers SET total_tips = total_tips + 1, total_amount = total_amount + ?, fees_paid = fees_paid + ?, last_tip = ? WHERE address = ?`)
          .run(eventData.amount + eventData.fee, eventData.fee, timestamp, eventData.tipper);
      } else {
        db.prepare(`INSERT INTO tippers (address, total_tips, total_amount, fees_paid, first_tip, last_tip) VALUES (?, 1, ?, ?, ?, ?)`)
          .run(eventData.tipper, eventData.amount + eventData.fee, eventData.fee, timestamp, timestamp);
        updateDailyStats(today, 'new_tippers');
      }
      
      updateDailyStats(today, 'tips_count');
      updateDailyStats(today, 'tips_volume', eventData.amount);
      updateLeaderboard();
      console.log(`💝 Tip: ${eventData.amount} to ${eventData.creator}`);
      break;

    case 'fee-collected':
      db.prepare(`INSERT INTO fees (tip_id, amount, timestamp) VALUES (?, ?, ?)`)
        .run(eventData['tip-id'], eventData.amount, timestamp);
      updateDailyStats(today, 'fees_collected', eventData.amount);
      console.log(`💵 Fee: ${eventData.amount}`);
      break;

    case 'tip-withdrawn':
      console.log(`💸 Withdrawal: ${eventData.amount} by ${eventData.creator}`);
      break;

    case 'content-posted':
      db.prepare(`INSERT INTO content (content_id, creator, content_type, title, created_at) VALUES (?, ?, ?, ?, ?)`)
        .run(eventData['content-id'], eventData.creator, eventData['content-type'], eventData.title, timestamp);
      db.prepare(`UPDATE creators SET content_count = content_count + 1 WHERE address = ?`).run(eventData.creator);
      console.log(`📝 Content: "${eventData.title}" by ${eventData.creator}`);
      break;

    case 'creator-verified':
      db.prepare(`UPDATE creators SET verified = 1 WHERE address = ?`).run(eventData.creator);
      console.log(`✅ Verified: ${eventData.creator}`);
      break;
  }
};

// API Routes
app.post('/api/tip-events', authMiddleware, (req, res) => {
  try {
    const events = extractEventData(req.body);
    for (const { data, blockHeight, txId } of events) {
      if (data && data.event) processEvent(data, blockHeight, txId);
    }
    res.status(200).json({ success: true, processed: events.length });
  } catch (error) {
    console.error('Error:', error);
    res.status(500).json({ error: error.message });
  }
});

// Analytics endpoints
app.get('/api/stats', (req, res) => {
  res.json({
    totalCreators: db.prepare('SELECT COUNT(*) as c FROM creators').get().c,
    totalTippers: db.prepare('SELECT COUNT(*) as c FROM tippers').get().c,
    totalTips: db.prepare('SELECT COUNT(*) as c FROM tips').get().c,
    totalVolume: db.prepare('SELECT COALESCE(SUM(amount), 0) as s FROM tips').get().s,
    totalFees: db.prepare('SELECT COALESCE(SUM(amount), 0) as s FROM fees').get().s,
    totalContent: db.prepare('SELECT COUNT(*) as c FROM content').get().c
  });
});

app.get('/api/stats/daily', (req, res) => {
  const days = parseInt(req.query.days) || 30;
  res.json(db.prepare('SELECT * FROM daily_stats ORDER BY date DESC LIMIT ?').all(days));
});

app.get('/api/leaderboard', (req, res) => {
  const limit = parseInt(req.query.limit) || 20;
  res.json(db.prepare('SELECT * FROM leaderboard ORDER BY rank ASC LIMIT ?').all(limit));
});

app.get('/api/creators/:address', (req, res) => {
  const creator = db.prepare('SELECT * FROM creators WHERE address = ?').get(req.params.address);
  if (!creator) return res.status(404).json({ error: 'Creator not found' });
  res.json(creator);
});

app.get('/api/tips/recent', (req, res) => {
  const limit = parseInt(req.query.limit) || 20;
  res.json(db.prepare('SELECT * FROM tips ORDER BY timestamp DESC LIMIT ?').all(limit));
});

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.listen(PORT, () => {
  console.log(`💝 Tipping Chainhook Server on port ${PORT}`);
});

module.exports = app;
