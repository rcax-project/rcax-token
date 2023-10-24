// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "libraries/AvatarContracts.sol";

/// @custom:oz-upgrades-unsafe-allow external-library-linking
contract RCAXTokenV2 is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, ERC20PermitUpgradeable, ERC20VotesUpgradeable, ERC1155HolderUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 private constant _cap = 72290000 * 10**18; // Maximum supply cap of RCAX tokens
    uint256 private constant BASE_REWARD = 60 * 10**18; // Base avatar burn reward
    uint32 private constant HALVING_PERIOD_IN_BLOCKS = 7257600; // Approximately 24 weeks on Polygon (assuming 2s block time)
    uint256 private constant DEPLOYMENT_BLOCK_NUMBER = 49074972; // The block number when the contract was deployed
    address private constant DEV_WALLET = 0xB5C42f30cEAE2032F22d364E33A5BaEfA1A043FF; // RCAX development fund
    address private constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD; // Official burn address
    address private constant RCAX_TOKEN_V1_ADDRESS = 0xC99BD85BA824De949cf088375225E3FdCDB6696C;
    uint256 private constant RCAX_CLASSIC_CONVERT_PERIOD_IN_BLOCKS = 3628800; // 12 weeks

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) external initializer {
        __ERC20_init("RCAX", "RCAX");
        __ERC20Burnable_init();
        __ERC20Permit_init("RCAX");
        __ERC20Votes_init();
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyOwner
    override
    {}

    function _update(address from, address to, uint256 value)
    internal
    override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
    public
    view
    override(ERC20PermitUpgradeable, NoncesUpgradeable)
    returns (uint256)
    {
        return super.nonces(owner);
    }

    function cap() public view virtual returns (uint256) {
        return _cap;
    }

    function _checkedMintToAddress(address to, uint256 amount) internal {
        require(totalSupply() + amount <= _cap, "Mint would exceed the hard cap of 72,290,000");
        _mint(to, amount);
    }

    function convertClassicTokens(uint256 amount) public {
        require(block.number <= DEPLOYMENT_BLOCK_NUMBER + RCAX_CLASSIC_CONVERT_PERIOD_IN_BLOCKS, "RCAX Classic convert period has passed");

        _burnRCAXClassicTokens(msg.sender, amount);
    }

    function _burnRCAXClassicTokens(address from, uint256 amount) internal {
        require(IERC20(RCAX_TOKEN_V1_ADDRESS).balanceOf(from) >= amount, "User does not have enough RCAX Classic tokens");

        if (from != address(this)) {
            require(IERC20(RCAX_TOKEN_V1_ADDRESS).allowance(from, address(this)) >= amount, "Please allow the contract to spend your RCAX Classic tokens");
        }

        try IERC20(RCAX_TOKEN_V1_ADDRESS).transferFrom(from, BURN_ADDRESS, amount) {
            // Successful transfer
            // Mint new RCAX tokens from burned Classic tokens 1:1
            _checkedMintToAddress(from, amount);
        } catch (bytes memory revertReason) {
            revert(string(revertReason));
        }
    }

    function _sendAvatar(address recipient, address tokenAddress, uint256 tokenId) internal {
        try IERC1155(tokenAddress).safeTransferFrom(address(this), recipient, tokenId, 1, "") {
            // Successful transfer
        } catch (bytes memory revertReason) {
            revert(string(revertReason));
        }
    }

    function _handleReceivedERC1155(address rewardReceiver, address tokenAddress, uint256 tokenId) internal {
        uint256 avatarBurnReward = getAvatarBurnReward(tokenAddress);

        require(avatarBurnReward > 0, "Token is not eligible for a burn reward");

        // Give avatar burn reward to sender
        _checkedMintToAddress(rewardReceiver, avatarBurnReward);

        // Mint an extra 15% to the RCAX development wallet
        _checkedMintToAddress(DEV_WALLET, (avatarBurnReward / 100) * 15);

        // Burn the received Avatar
        _sendAvatar(BURN_ADDRESS, tokenAddress, tokenId);
    }

    function getAvatarBurnReward(address avatarAddress) public view returns (uint256) {
        if (AvatarContracts.isAvatarGen1(avatarAddress)) {
            return getAvatarBurnRewardBase() * 24;
        } else if (AvatarContracts.isAvatarGen2(avatarAddress)) {
            return getAvatarBurnRewardBase() * 12;
        } else if (AvatarContracts.isAvatarGen3(avatarAddress)) {
            return getAvatarBurnRewardBase() * 0;
        } else if (AvatarContracts.isAvatarGen4(avatarAddress)) {
            return getAvatarBurnRewardBase() * 0;
        } else if (AvatarContracts.isAvatarAwwDripMemeSingu(avatarAddress)) {
            return getAvatarBurnRewardBase() * 4;
        } else if (AvatarContracts.isAvatarRC2022(avatarAddress)) {
            return getAvatarBurnRewardBase() / 10;
        } else if (AvatarContracts.isAvatarSBLVII(avatarAddress)) {
            return getAvatarBurnRewardBase() / 10;
        }

        return 0;
    }

    function getAvatarBurnRewardBase() public view returns (uint256) {
        uint256 blocksSinceDeployment = block.number - DEPLOYMENT_BLOCK_NUMBER;

        uint256 halvings = blocksSinceDeployment / HALVING_PERIOD_IN_BLOCKS;

        return BASE_REWARD / (2**halvings);
    }

    function onERC1155Received(
        address,
        address from,
        uint256 id,
        uint256 value,
        bytes memory
    ) public override returns (bytes4) {
        require(value == 1);

        _handleReceivedERC1155(from, msg.sender, id);

        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory
    ) public override returns (bytes4) {
        for (uint256 i = 0; i < ids.length; i++) {
            require(values[i] == 1);
            _handleReceivedERC1155(from, msg.sender, ids[i]);
        }

        return this.onERC1155BatchReceived.selector;
    }
}
