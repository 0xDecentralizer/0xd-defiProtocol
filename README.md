# 0xD Protocol

A fully decentralized stablecoin protocol where your collateral works harder than you do.

## What Is This?

> **Note**: This project is based on the [Advanced Foundry course by Cyfrin Updraft](https://updraft.cyfrin.io/), but implemented entirely by me (0xdecentralizer) as a learning exercise. It's **not audited**, **may have bugs**, and is **for educational purposes only** — not for real-world use.

0xD Protocol is an **exogenous, decentralized, crypto-collateralized stablecoin** system that maintains a 1 DSC = $1 USD peg. Think of it like MakerDAO's DAI, but stripped down to the essentials: no governance, no fees, just pure over-collateralized stability backed by WETH and WBTC.

**Properties:**
- **Exogenous Collateral**: Backed by real crypto assets (WETH, WBTC)
- **Decentralized Stability**: Algorithmic, no central authority
- **Dollar Pegged**: Always targets $1 USD
- **Over-collateralized**: System maintains >200% collateralization at all times

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Decentralized Stablecoin                     │
│                     (DSC Token - ERC20)                         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        DSCEngine                                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐  │
│  │  Collateral │  │   Minting   │  │    Liquidation Engine   │  │
│  │  Management │  │   & Burning │  │                         │  │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OracleLib                                  │
│              (Chainlink Price Feeds + Stale Check)              │
└─────────────────────────────────────────────────────────────────┘
```

## Core Components

### DecentralizedStableCoin (`src/DecentralizedStableCoin.sol`)
The ERC20 stablecoin token. Only the DSCEngine can mint and burn tokens.

### DSCEngine (`src/DSCEngine.sol`)
The heart of the protocol. Handles:
- **Collateral Deposits**: Users deposit WETH/WBTC as collateral
- **DSC Minting**: Users mint DSC against their collateral
- **Health Factor Monitoring**: Ensures system remains over-collateralized
- **Liquidations**: Under-collateralized positions get liquidated with 10% bonus

### OracleLib (`src/libraries/OracleLib.sol`)
Chainlink price feed integration with stale data protection (3-hour timeout).

## Key Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Liquidation Threshold | 200% | Collateral must be ≥2x the debt |
| Liquidation Bonus | 10% | Incentive for liquidators |
| Minimum Health Factor | 1.0 | Below this, positions are liquidatable |
| Supported Collateral | WETH, WBTC | Only these tokens are accepted |
| Oracle Stale Timeout | 3 hours | Price data older than this is rejected |

## Getting Started

### Prerequisites

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Installation

```bash
git clone https://github.com/your-username/0xd-defiProtocol.git
cd 0xd-defiProtocol
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test
```

### Deploy to Local (Anvil)

```bash
# Start local node
anvil

# Deploy
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

### Deploy to Sepolia

```bash
forge script script/DeployDSC.s.sol:DeployDSC \
  --rpc-url <your-rpc-url> \
  --private-key <your-private-key> \
  --broadcast
```

## Usage Examples

### Deposit Collateral and Mint DSC

```solidity
// Deposit 1 WETH (assuming 18 decimals)
engine.depositCollateral(wethAddress, 1e18);

// Mint 1500 DSC (using 200% collateralization)
engine.mintDsc(1500e18);
```

### Redeem Collateral

```solidity
// Burn 500 DSC and get back collateral
engine.redeemCollateralForDsc(wethAddress, 500e18 / 3000e8, 500e18);
```

### Check Health Factor

```solidity
uint256 healthFactor = engine.getHealthFactor(userAddress);
// healthFactor >= 1e18 means healthy
// healthFactor < 1e18 means liquidatable
```

## Testing

The protocol includes comprehensive testing:

- **Unit Tests**: `test/unit/DSCEngineTest.t.sol`
- **Fuzz Tests**: `test/fuzz/Invariants.t.sol`
- **Invariant Tests**: `test/handler/Handler.t.sol`

Run all tests:

```bash
forge test -vvv
```

## Security Considerations

- **Reentrancy Protection**: DSCEngine uses OpenZeppelin's ReentrancyGuard
- **Health Factor Checks**: All state changes validate health factor remains safe
- **Oracle Staleness**: Price feeds are checked for freshness (3-hour timeout)
- **Over-collateralization**: System enforces 200% collateralization ratio

## Disclaimer

**This project is for learning purposes only.**

- Based on [Advanced Foundry course by Cyfrin Updraft](https://updraft.cyfrin.io/)
- Implemented 100% by me as a learning exercise
- **Not audited** — use at your own risk
- **May contain bugs** — do not use with real funds
- Not intended for production deployment

If you find bugs, please open an issue! It's a great learning opportunity for both of us.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with [Foundry](https://book.getfoundry.sh/)
- Inspired by MakerDAO's DSS system
- Price feeds powered by [Chainlink](https://chain.link/)
- Security patterns from [OpenZeppelin](https://www.openzeppelin.com/)

---

**Remember**: In DeFi, your collateral is your collateral. Don't get liquidated. 🚀
