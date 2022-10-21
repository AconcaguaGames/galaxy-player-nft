pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error InvalidPaymentAddress();
error InvalidSignerAddress();
error InvalidBoxId();
error InvalidBoxPrice();
error InvalidBoxQuantity();
error BoxNotExists();
error BoxAlreadyExists();
error BoxAlreadyDisabled();
error BoxAlreadyEnabled();
error BoxNotEnabled();
error BoxFreeOnlyWithSignature();
error BoxNotFree();
error BoxFree();
error BoxSoldWithToken();
error BoxSoldWithCoin();
error BoxSoldOnlyWithSignature();
error BoxSoldWithNoSignature();
error BoxInvalidSignature();
error BoxSignatureAlreadyUsed();
error BuyBoxCoinWrongPrice();
error BuyBoxCoinNotSent();
error BuyBoxTokenNotSent();
error BoxSoldOut();

/**
 * @dev GalaxyPlayer is a ERC721 token sold in boxes.
 *
 * The contract owner can add new boxes.
 * Each box has a price and can be sold usign the network coin or ERC20 tokens.
 * Each box has a quantity. This is how many NFTs will be minted when the user buys the box.
 * A box can be disabled/enabled by the owner. A disabled box can’t be bought.
 * To allow whitelists, a box can be created to be bought only with a valid signature from the signer.
 * The owner can create free boxes too. Free boxes always need a valid signature to be bought.
 * A box can have a maxSupply. A zero maxSupply means unlimited supply.
 */
contract GalaxyPlayer is ERC721Enumerable, Ownable, Pausable {

  using ECDSA for bytes32;

  struct BoxStruct {
      uint256 price;
      uint256 maxSupply;
      bool enabled;
      bool withToken;
      bool onlyWithSignature;
      uint8 quantity;
      IERC20 token;
  }

  address payable public paymentAddress;
  address public signerAddress;
  string public baseTokenURI;
  uint256 public currentId;
  uint256 public currentSoldBoxId;

  // boxId -> BoxStruct
  mapping(uint256 => BoxStruct) public boxes;
  // tokenId -> soldBoxId
  mapping(uint256 => uint256) public soldBoxByToken;
  // soldBoxId -> boxId
  mapping(uint256 => uint256) public boxBySoldBox;
  // boxId -> supply
  mapping(uint256 => uint256) public supplyByBox;
  // signature nonce -> used
  mapping(uint256 => bool) public signatureUsed;


  /**
   * @dev Emitted when a new box is bought
   */
  event BoxPaid(
    uint256 indexed soldBoxId,
    address indexed buyer,
    uint256 indexed box,
    uint256 price,
    address tokenAddress,
    uint256[] tokenIds
  );

  /**
   * @dev Emitted when a new box sold with coins is added
   */
  event BoxWithCoinAdded(
    uint256 indexed box,
    uint256 price,
    uint8 quantity,
    uint256 maxSupply,
    bool onlyWithSignature
  );

  /**
   * @dev Emitted when a new box sold with tokens is added
   */
  event BoxWithTokenAdded(
    uint256 indexed box,
    uint256 price,
    uint8 quantity,
    uint256 maxSupply,
    bool onlyWithSignature,
    IERC20 token
  );

  /**
   * @dev Emitted when a new free box is added
   */
  event BoxFreeAdded(
    uint256 indexed box,
    uint8 quantity,
    uint256 maxSupply
  );

  /**
   * @dev Emitted when a box is disabled
   */
  event BoxDisabled(
    uint256 indexed box
  );

  /**
   * @dev Emitted when a box is enabled
   */
  event BoxEnabled(
    uint256 indexed box
  );

  /**
   * @dev Emitted when a box price is changed
   */
  event BoxPriceChanged(
    uint256 indexed box,
    uint256 price
  );

  /**
   * @dev Emitted when a box onlyWithSignature attribute is changed
   */
  event BoxOnlyWithSignatureUpdated(
    uint256 indexed box,
    bool onlyWithSignature
  );

  /**
   * @dev Emitted when the payment address is changed
   */
  event PaymentAddressUpdated(
    address indexed paymentAddress
  );

  /**
   * @dev Emitted when the signer address is changed
   */
  event SignerAddressUpdated(
    address indexed signerAddress
  );

  /**
   * @dev Emitted when the baseTokenURI is changed
   */
  event BaseTokenUriUpdated(
    string baseTokenURI
  );

  /**
   * @dev Call the ERC721 constructor with the token name and symbol, and then
   * set the payment and signer address.
   */
  constructor(address newPaymentAddress, address newSignerAddress) ERC721("GalaxyPlayer", "GXYPL") {
    setPaymentAddress(newPaymentAddress);
    setSignerAddress(newSignerAddress);
  }

  /**
   * @dev Modifier to check for a valid boxId.
   */
  modifier validBoxId(uint256 boxId) {
    if (boxId == 0) {
      revert InvalidBoxId();
    }
    _;
  }

  /**
   * @dev Modifier to check for valid box attributes: price and quantity.
   */
  modifier validBoxAttributes(uint256 price, uint8 quantity) {
    if (price == 0) {
      revert InvalidBoxPrice();
    }
    if (quantity == 0) {
      revert InvalidBoxQuantity();
    }
    _;
  }

  /**
   * @dev Modifier to check if a box exists.
   */
  modifier boxExists(uint256 boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.quantity == 0) {
      revert BoxNotExists();
    }
    _;
  }

  /**
   * @dev Modifier to check if a box do not exists.
   */
  modifier boxNotExists(uint256 boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.quantity > 0) {
      revert BoxAlreadyExists();
    }
    _;
  }

  /**
   * @dev Modifier to check if a box is not free.
   */
  modifier boxNotFree(uint256 boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.price == 0) {
      revert BoxFree();
    }
    _;
  }

  /**
   * @dev Modifier to check a valid box to buy.
   */
  modifier validBoxToBuy(uint256 boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.quantity == 0) {
      revert BoxNotExists();
    }

    if (!boxData.enabled) {
      revert BoxNotEnabled();
    }

    if (boxData.maxSupply > 0 && supplyByBox[boxId] == boxData.maxSupply) {
      revert BoxSoldOut();
    }

    _;
  }

  /**
   * @dev Pause buy methods.
   */
  function pause() external onlyOwner {
      _pause();
  }

  /**
   * @dev Resume buy methods.
   */
  function unpause() external onlyOwner {
      _unpause();
  }

  /**
   * @dev Base URI for computing {tokenURI}.
   */
  function _baseURI() internal view override returns (string memory) {
    return baseTokenURI;
  }

  /**
   * @dev Update baseTokenURI used for computing {tokenURI} (onlyOwner).
   *
   * Emits a {BaseTokenUriUpdated} event.
   */
  function updateBaseURI(string calldata newBaseTokenURI) external onlyOwner {
    baseTokenURI = newBaseTokenURI;

    emit BaseTokenUriUpdated(newBaseTokenURI);
  }

  /**
   * @dev Update paymentAddress (onlyOwner).
   *
   * Emits a {PaymentAddressUpdated} event.
   */
  function setPaymentAddress(address newPaymentAddress) public onlyOwner {
    if (newPaymentAddress == address(0)) {
      revert InvalidPaymentAddress();
    }

    paymentAddress = payable(newPaymentAddress);

    emit PaymentAddressUpdated(newPaymentAddress);
  }

  /**
   * @dev Update signerAddress (onlyOwner).
   *
   * Emits a {SignerAddressUpdated} event.
   */
  function setSignerAddress(address newSignerAddress) public onlyOwner {
    if (newSignerAddress == address(0)) {
      revert InvalidSignerAddress();
    }

    signerAddress = newSignerAddress;

    emit SignerAddressUpdated(newSignerAddress);
  }

  /**
   * @dev Adds a new box paid with network coin (onlyOwner).
   *
   * Emits a {BoxWithCoinAdded} and a {BoxEnabled} event.
   */
  function addBox(uint256 boxId, uint256 price, uint8 quantity, uint256 maxSupply, bool onlyWithSignature) external
    onlyOwner validBoxId(boxId) validBoxAttributes(price, quantity) boxNotExists(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    boxData.price = price;
    boxData.quantity = quantity;
    boxData.maxSupply = maxSupply;
    boxData.onlyWithSignature = onlyWithSignature;
    boxData.enabled = true;

    emit BoxWithCoinAdded(boxId, price, quantity, maxSupply, onlyWithSignature);
    emit BoxEnabled(boxId);
  }

  /**
   * @dev Adds a new box paid with network coin (onlyOwner).
   *
   * Emits a {BoxWithCoinAdded} and a {BoxEnabled} event.
   */
  function addBoxWithToken(uint256 boxId, uint256 price, uint8 quantity, uint256 maxSupply, bool onlyWithSignature, IERC20 tokenAddress) external
    onlyOwner validBoxId(boxId) validBoxAttributes(price, quantity) boxNotExists(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    boxData.price = price;
    boxData.quantity = quantity;
    boxData.maxSupply = maxSupply;
    boxData.onlyWithSignature = onlyWithSignature;
    boxData.enabled = true;
    boxData.withToken = true;
    boxData.token = tokenAddress;

    emit BoxWithTokenAdded(boxId, price, quantity, maxSupply, onlyWithSignature, tokenAddress);
    emit BoxEnabled(boxId);
  }

  /**
   * @dev Adds a new free box minted only with signature (onlyOwner).
   *
   * Emits a {BoxFreeAdded} and a {BoxEnabled} event.
   */
  function addBoxFree(uint256 boxId, uint8 quantity, uint256 maxSupply) external
    onlyOwner validBoxId(boxId) boxNotExists(boxId) {

    if (quantity == 0) {
      revert InvalidBoxQuantity();
    }

    BoxStruct storage boxData = boxes[boxId];

    boxData.quantity = quantity;
    boxData.maxSupply = maxSupply;
    boxData.onlyWithSignature = true;
    boxData.enabled = true;

    emit BoxFreeAdded(boxId, quantity, maxSupply);
    emit BoxEnabled(boxId);
  }

  /**
   * @dev Disable an enabled box (onlyOwner).
   *
   * Emits a {BoxDisabled} event.
   */
  function disableBox(uint256 boxId) external onlyOwner validBoxId(boxId) boxExists(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (!boxData.enabled) {
      revert BoxAlreadyDisabled();
    }

    boxData.enabled = false;

    emit BoxDisabled(boxId);
  }

  /**
   * @dev Enable a disabled box (onlyOwner).
   *
   * Emits a {BoxEnabled} event.
   */
  function enableBox(uint256 boxId) external onlyOwner validBoxId(boxId) boxExists(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.enabled) {
      revert BoxAlreadyEnabled();
    }

    boxData.enabled = true;

    emit BoxEnabled(boxId);
  }

  /**
   * @dev Update onlyWithSignature attribute on a box (onlyOwner).
   * @dev Can't update onlyWithSignature on free boxes.
   *
   * Emits a {BoxOnlyWithSignatureUpdated} event.
   */
  function changeBoxOnlyWithSignature(uint256 boxId, bool onlyWithSignature) external onlyOwner validBoxId(boxId) boxExists(boxId) boxNotFree(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    boxData.onlyWithSignature = onlyWithSignature;

    emit BoxOnlyWithSignatureUpdated(boxId, onlyWithSignature);
  }

  /**
   * @dev Change the price of a existing box (onlyOwner).
   * @dev Can't update price on free boxes.
   *
   * Emits a {BoxPriceChanged} event.
   */
  function changeBoxPrice(uint256 boxId, uint256 price) external onlyOwner validBoxId(boxId) boxExists(boxId) boxNotFree(boxId) {
    if (price == 0) {
      revert InvalidBoxPrice();
    }

    BoxStruct storage boxData = boxes[boxId];

    boxData.price = price;

    emit BoxPriceChanged(boxId, price);
  }

  /**
   * @dev Public function to buy a box using network coint and mint box.quantity NFTs.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function buyBox(uint256 boxId) external payable whenNotPaused validBoxToBuy(boxId) boxNotFree(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.withToken) {
      revert BoxSoldWithToken();
    }

    if (boxData.onlyWithSignature) {
      revert BoxSoldOnlyWithSignature();
    }

    if (msg.value != boxData.price) {
      revert BuyBoxCoinWrongPrice();
    }

    mintByBox(boxId);

    (bool success, ) = paymentAddress.call{value: msg.value}("");

    if (!success) {
      revert BuyBoxCoinNotSent();
    }
  }

  /**
   * @dev Public function to buy a box using tokens and mint box.quantity NFTs.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function buyBoxWithToken(uint256 boxId) external whenNotPaused validBoxToBuy(boxId) boxNotFree(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (!boxData.withToken) {
      revert BoxSoldWithCoin();
    }

    if (boxData.onlyWithSignature) {
      revert BoxSoldOnlyWithSignature();
    }

    mintByBox(boxId);

    if (!boxData.token.transferFrom(msg.sender, address(paymentAddress), boxData.price)) {
      revert BuyBoxTokenNotSent();
    }
  }

  /**
   * @dev Public function to buy a signature only box using network coint and mint box.quantity NFTs.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function buyBoxWithSignature(uint256 boxId, uint256 nonce, bytes calldata signature) external payable whenNotPaused validBoxToBuy(boxId) boxNotFree(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.withToken) {
      revert BoxSoldWithToken();
    }

    if (!boxData.onlyWithSignature) {
      revert BoxSoldWithNoSignature();
    }

    if (!verifyBoxSignature(boxId, nonce, signature)) {
      revert BoxInvalidSignature();
    }

    if (signatureUsed[nonce]) {
      revert BoxSignatureAlreadyUsed();
    }

    if (msg.value != boxData.price) {
      revert BuyBoxCoinWrongPrice();
    }

    signatureUsed[nonce] = true;

    mintByBox(boxId);

    (bool success, ) = paymentAddress.call{value: msg.value}("");

    if (!success) {
      revert BuyBoxCoinNotSent();
    }
  }

  /**
   * @dev Public function to buy a signature only box using tokens and mint box.quantity NFTs.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function buyBoxWithTokenWithSignature(uint256 boxId, uint256 nonce, bytes calldata signature) external whenNotPaused validBoxToBuy(boxId) boxNotFree(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (!boxData.withToken) {
      revert BoxSoldWithCoin();
    }

    if (!boxData.onlyWithSignature) {
      revert BoxSoldWithNoSignature();
    }

    if (!verifyBoxSignature(boxId, nonce, signature)) {
      revert BoxInvalidSignature();
    }

    if (signatureUsed[nonce]) {
      revert BoxSignatureAlreadyUsed();
    }

    signatureUsed[nonce] = true;

    mintByBox(boxId);

    if (!boxData.token.transferFrom(msg.sender, address(paymentAddress), boxData.price)) {
      revert BuyBoxTokenNotSent();
    }
  }

  /**
   * @dev Public function to buy a free box using signature and mint box.quantity NFTs.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function buyBoxFree(uint256 boxId, uint256 nonce, bytes calldata signature) external whenNotPaused validBoxToBuy(boxId) {
    BoxStruct storage boxData = boxes[boxId];

    if (boxData.price > 0) {
      revert BoxNotFree();
    }

    if (!boxData.onlyWithSignature) {
      revert BoxSoldWithNoSignature();
    }

    if (!verifyBoxSignature(boxId, nonce, signature)) {
      revert BoxInvalidSignature();
    }

    if (signatureUsed[nonce]) {
      revert BoxSignatureAlreadyUsed();
    }

    signatureUsed[nonce] = true;

    mintByBox(boxId);
  }

  /**
   * @dev Internal function to mint box.quantity NFTs from a box.
   *
   * Emits a {BoxPaid} event and a {Transfer} event for each NFT minted.
   */
  function mintByBox(uint256 boxId) internal {
    BoxStruct storage boxData = boxes[boxId];

    currentSoldBoxId++;

    supplyByBox[boxId]++;

    uint256[] memory tokenIds = new uint256[](boxData.quantity);

    for (uint8 i = 0; i < boxData.quantity; i++) {
      currentId++;

      _mint(msg.sender, currentId);

      soldBoxByToken[currentId] = currentSoldBoxId;
      boxBySoldBox[currentSoldBoxId] = boxId;

      tokenIds[i] = currentId;
    }

    emit BoxPaid(currentSoldBoxId, msg.sender, boxId, boxData.price, address(boxData.token), tokenIds);
  }

  function verifyBoxSignature(
    uint256 boxId,
    uint256 nonce,
    bytes calldata signature
  ) public view returns (bool) {
    bytes32 criteriaMessageHash = keccak256(
      abi.encodePacked(msg.sender, address(this), block.chainid, boxId, nonce)
    );
    bytes32 ethSignedMessageHash = criteriaMessageHash.toEthSignedMessageHash();

    return ethSignedMessageHash.recover(signature) == signerAddress;
  }
}