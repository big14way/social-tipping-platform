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

## WalletConnect Integration

This project includes a fully-functional React dApp with WalletConnect v2 integration for seamless interaction with Stacks blockchain wallets.

### Features

- **🔗 Multi-Wallet Support**: Connect with any WalletConnect-compatible Stacks wallet
- **✍️ Transaction Signing**: Sign messages and submit transactions directly from the dApp
- **📝 Contract Interactions**: Call smart contract functions on Stacks testnet
- **🔐 Secure Connection**: End-to-end encrypted communication via WalletConnect relay
- **📱 QR Code Support**: Easy mobile wallet connection via QR code scanning

### Quick Start

#### Prerequisites

- Node.js (v16.x or higher)
- npm or yarn package manager
- A Stacks wallet (Xverse, Leather, or any WalletConnect-compatible wallet)

#### Installation

```bash
cd dapp
npm install
```

#### Running the dApp

```bash
npm start
```

The dApp will open in your browser at `http://localhost:3000`

#### Building for Production

```bash
npm run build
```

### WalletConnect Configuration

The dApp is pre-configured with:

- **Project ID**: 1eebe528ca0ce94a99ceaa2e915058d7
- **Network**: Stacks Testnet (Chain ID: `stacks:2147483648`)
- **Relay**: wss://relay.walletconnect.com
- **Supported Methods**:
  - `stacks_signMessage` - Sign arbitrary messages
  - `stacks_stxTransfer` - Transfer STX tokens
  - `stacks_contractCall` - Call smart contract functions
  - `stacks_contractDeploy` - Deploy new smart contracts

### Project Structure

```
dapp/
├── public/
│   └── index.html
├── src/
│   ├── components/
│   │   ├── WalletConnectButton.js      # Wallet connection UI
│   │   └── ContractInteraction.js       # Contract call interface
│   ├── contexts/
│   │   └── WalletConnectContext.js     # WalletConnect state management
│   ├── hooks/                            # Custom React hooks
│   ├── utils/                            # Utility functions
│   ├── config/
│   │   └── stacksConfig.js             # Network and contract configuration
│   ├── styles/                          # CSS styling
│   ├── App.js                           # Main application component
│   └── index.js                         # Application entry point
└── package.json
```

### Usage Guide

#### 1. Connect Your Wallet

Click the "Connect Wallet" button in the header. A QR code will appear - scan it with your mobile Stacks wallet or use the desktop wallet extension.

#### 2. Interact with Contracts

Once connected, you can:

- View your connected address
- Call read-only contract functions
- Submit contract call transactions
- Sign messages for authentication

#### 3. Disconnect

Click the "Disconnect" button to end the WalletConnect session.

### Customization

#### Updating Contract Configuration

Edit `src/config/stacksConfig.js` to point to your deployed contracts:

```javascript
export const CONTRACT_CONFIG = {
  contractName: 'your-contract-name',
  contractAddress: 'YOUR_CONTRACT_ADDRESS',
  network: 'testnet' // or 'mainnet'
};
```

#### Adding Custom Contract Functions

Modify `src/components/ContractInteraction.js` to add your contract-specific functions:

```javascript
const myCustomFunction = async () => {
  const result = await callContract(
    CONTRACT_CONFIG.contractAddress,
    CONTRACT_CONFIG.contractName,
    'your-function-name',
    [functionArgs]
  );
};
```

### Technical Details

#### WalletConnect v2 Implementation

The dApp uses the official WalletConnect v2 Sign Client with:

- **@walletconnect/sign-client**: Core WalletConnect functionality
- **@walletconnect/utils**: Helper utilities for encoding/decoding
- **@walletconnect/qrcode-modal**: QR code display for mobile connection
- **@stacks/connect**: Stacks-specific wallet integration
- **@stacks/transactions**: Transaction building and signing
- **@stacks/network**: Network configuration for testnet/mainnet

#### BigInt Serialization

The dApp includes BigInt serialization support for handling large numbers in Clarity contracts:

```javascript
BigInt.prototype.toJSON = function() { return this.toString(); };
```

### Supported Wallets

Any wallet supporting WalletConnect v2 and Stacks blockchain, including:

- **Xverse Wallet** (Recommended)
- **Leather Wallet** (formerly Hiro Wallet)
- **Boom Wallet**
- Any other WalletConnect-compatible Stacks wallet

### Troubleshooting

**Connection Issues:**
- Ensure your wallet app supports WalletConnect v2
- Check that you're on the correct network (testnet vs mainnet)
- Try refreshing the QR code or restarting the dApp

**Transaction Failures:**
- Verify you have sufficient STX for gas fees
- Confirm the contract address and function names are correct
- Check that post-conditions are properly configured

**Build Errors:**
- Clear node_modules and reinstall: `rm -rf node_modules && npm install`
- Ensure Node.js version is 16.x or higher
- Check for dependency conflicts in package.json

### Resources

- [WalletConnect Documentation](https://docs.walletconnect.com/)
- [Stacks.js Documentation](https://docs.stacks.co/build-apps/stacks.js)
- [Xverse WalletConnect Guide](https://docs.xverse.app/wallet-connect)
- [Stacks Blockchain Documentation](https://docs.stacks.co/)

### Security Considerations

- Never commit your private keys or seed phrases
- Always verify transaction details before signing
- Use testnet for development and testing
- Audit smart contracts before mainnet deployment
- Keep dependencies updated for security patches

### License

This dApp implementation is provided as-is for integration with the Stacks smart contracts in this repository.

