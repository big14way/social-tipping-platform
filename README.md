# Social Tipping Platform

Tip your favorite content creators with STX. Chainhook integration for real-time analytics and leaderboards.

## Features

- **Creator Profiles**: Register username, bio, verified status
- **Content Tipping**: Tip specific content or creators directly
- **Supporter Tracking**: Track who supports whom
- **Leaderboards**: Real-time creator rankings
- **Milestones & Badges**: Achievement system

## Clarity 4 Features

| Feature | Usage |
|---------|-------|
| `stacks-block-time` | Activity timestamps |
| `restrict-assets?` | Safe tip transfers |
| `to-ascii?` | Human-readable creator info |

## Fee Structure

| Fee | Rate | Applied |
|-----|------|---------|
| Protocol Fee | 2.5% | On every tip |

Minimum tip: 0.1 STX

## Chainhook Events

| Event | Description |
|-------|-------------|
| `creator-registered` | New creator signup |
| `tip-sent` | Tip transaction |
| `tip-withdrawn` | Creator withdrawal |
| `content-posted` | New content |
| `fee-collected` | Protocol fee |
| `milestone-reached` | Achievement unlocked |

## Quick Start

```bash
# Deploy contracts
cd social-tipping-platform
clarinet check && clarinet test

# Start Chainhook server
cd server && npm install && npm start

# Register chainhook
chainhook predicates scan ./chainhooks/tip-events.json --testnet
```

## Contract Functions

```clarity
;; Register as creator
(register-creator username bio)

;; Post content
(post-content content-type content-hash title)

;; Send tip
(send-tip creator amount content-id message)

;; Withdraw earnings
(withdraw-earnings amount)
```

## API Endpoints

```bash
GET /api/stats           # Platform statistics
GET /api/stats/daily     # Daily metrics
GET /api/leaderboard     # Top creators
GET /api/creators/:addr  # Creator profile
GET /api/tips/recent     # Recent tips
```

## Example

```typescript
// Register as creator
await registerCreator("alice", "Digital artist and content creator");

// Post content
const contentId = await postContent("video", contentHash, "Tutorial #5");

// Tipper sends 5 STX
await sendTip(creatorAddress, 5000000, contentId, "Love your work!");
// Creator receives 4.875 STX (2.5% fee)

// Creator withdraws
await withdrawEarnings(4875000);
```

## License

MIT License

## Testnet Deployment

### tip-reputation
- **Status**: ✅ Deployed to Testnet
- **Transaction ID**: `861664bc9c1ddabc9df6053c72830ee40a3b4879bf49477c35dd8ce19eb24d98`
- **Deployer**: `ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM`
- **Explorer**: https://explorer.hiro.so/txid/861664bc9c1ddabc9df6053c72830ee40a3b4879bf49477c35dd8ce19eb24d98?chain=testnet
- **Deployment Date**: December 22, 2025

### Network Configuration
- Network: Stacks Testnet
- Clarity Version: 4
- Epoch: 3.3
- Chainhooks: Configured and ready

### Contract Features
- Comprehensive validation and error handling
- Event emission for Chainhook monitoring
- Fully tested with `clarinet check`
- Production-ready security measures
