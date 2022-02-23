# Notional fCash as collateral

## About fCash
Notional borrowing and lending positions are stored as [fCash](https://docs.notional.finance/notional-v2/notional-v2-basics/fcash).

fCash positions can be positive or negative. If positive they are equivalent for a lending position, and are redeemable at maturity for their face value. If negative they are borrowing positions.

We want to use fCash lending positions as collateral. Given that we know that they are redeemable for their face value at maturity and their volatility is low, they are good assets for that purpose.

Accepting fCash as collateral also eases arbitraging and leverage between Notional an Yield. By taking positive fCash balances as collateral, we facilitate lending on Notional and borrowing from Yield.

fCash is kept internally in the Notional contracts, but there is a [proxy](https://github.com/notional-finance/contracts-v2/blob/master/contracts/external/actions/ERC1155Action.sol) that allows working with fCash as an ERC1155 token.

The Notional [proxy](0x1344A36A1B56144C3Bc62E7757377D288fDE0369) is deployed on the Ethereum mainnet. It has links to the [ERC1155](0xffd7531ed937f703b269815950cb75bdaaa341c9) and [Views](0xde14d5f07456c86f070c108a04ae2fafdbd2a939) proxies. Not sure but I think that you call all functions on the main proxy.

The fCash id is [built](https://github.com/notional-finance/contracts-v2/blob/master/contracts/internal/portfolio/TransferAssets.sol#L17-L47) from the currency id, maturity and asset type.

Currencies:
1: ETH
2: DAI
3: USDC
4: WBTC

The asset type for fCash is 1

The maturities are in strict 90 day intervals, with `x = 90 * 86400` as all valid maturities.

## fCash in Yield
A Join to handle ERC1155 assets is included in this folder. Each Join1155 contract can handle only *one* token type from a given ERC1155 contract, meaning that we will need a Join1155 for fDAI-Jun22, another for fDAI-Sep22, and so on.

The Ladle can't natively transfer ERC1155 assets, so a simple module is included to add this functionality. The ERC1155 contract needs to be added as a `token` to the Ladle registry. The Ladle needs to be approved to move ERC1155 tokens with `token.setApprovalForAll(ladle.address, true)`. There are no off-chain signatures.

Pricing fCash accurately would be rather complex, but we can price it at face value given that we know that it will eventually be worth its face value, and that it has limited volatility. Still, a collateralization ratio above 100% would be recommended.

With these tools, each fCash token can be added as a separate asset in the Cauldron, get its own Join, and be registered as an ilk for any base.