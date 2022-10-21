# GalaxyPlayer ERC721 Token

## Boxes

- The NFTs are sold in boxes.
- The owner can add new boxes.
- Each box has a price.
- Each box is sold with the network coin or with a token.
- If the box is sold with a token, the token address must be set.
- This setting and the token address can’t be changed.
- Each box has a quantity. This is how many NFTs will be minted when the user buys the box.
- To allow whitelists, a box can be created to be bought only with a valid signature from the signer. The signature is only valid for the signed box and only one time.
- The owner can change if a box needs a valid signature or not.
- The owner can create free boxes too. Free boxes always need a valid signature to be bought.
- The box price can be changed only on not free boxes.
- A box can be disabled/enabled by the owner. A disabled box can’t be bought.
- A box can have a maxSupply. The maxSupply can’t be modified. A zero maxSupply means unlimited supply.
- The owner can pause the contract and all the buys functions are disabled until the contract is unpaused.

### Box Attributes

- Price: can be changed only if price > 0.
- maxSupply: 0 means unlimited. Can’t be changed.
- Enabled: true/false. When disabled the box can’t be bought.
- withToken: true/false. False means that the box is sold with network coins. Can’t be changed.
- Token: token address if the box is sold with tokens.
- onlyWithSignature: true/false. True means that the box is sold only with a whitelist. Can be changed only if price > 0.
- Quantity: how many NFTs will be minted when the box is bought. Can’t be changed.

