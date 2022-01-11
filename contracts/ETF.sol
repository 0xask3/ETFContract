//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "./IterableMapping.sol";

contract ETF is Ownable, ERC20PresetMinterPauser {
    using IterableMapping for IterableMapping.Map;

    IERC20 public token; //Deposit token
    uint256 public totalAllocation; //Total allocation points

    IterableMapping.Map private AssetsMap;

    IUniswapV2Router02 private router =
        IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);

    mapping(address => uint256) public depositAmount;
    mapping(address => mapping(address => uint256)) public investors;

    uint256 public totalShares;
    mapping(address => uint256) public userShares;

    uint16 public entryFee = 100; //10%
    uint16 public exitFee = 100; //10%

    constructor(
        address _token,
        address[] memory assets,
        uint256[] memory allocations
    ) ERC20PresetMinterPauser("ETF Token", "ETF") {
        token = IERC20(_token);
        uint256 len = assets.length;
        require(len == allocations.length, "Incorrect input");

        for (uint256 i = 0; i < len; i++) {
            AssetsMap.set(assets[i], allocations[i]);
            totalAllocation += allocations[i];
            IERC20(assets[i]).approve(address(router), ~uint256(0));
        }

        _setupRole(MINTER_ROLE, address(this));
        _revokeRole(MINTER_ROLE, _msgSender());

        token.approve(address(router), ~uint256(0));
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);

        uint256 fees = (amount * entryFee) / 1000;
        token.transfer(owner(), fees);
        amount = amount - fees;

        uint256 currentShares;
        (, uint256 poolBal) = getPrice();

        if (totalShares != 0) {
            currentShares = ((amount * totalShares) / poolBal);
        } else {
            currentShares = amount;
        }

        totalShares = totalShares + currentShares;

        _mint(msg.sender, currentShares);

        uint256 len = AssetsMap.size();
        address asset;
        uint256 allocation;

        for (uint256 i = 0; i < len; i++) {
            asset = AssetsMap.getKeyAtIndex(i);
            allocation = (amount * AssetsMap.get(asset)) / totalAllocation;

            swapTokenForAsset(asset, allocation);
        }
    }

    function withdrawAssets(uint256 shares, address withdrawAddress) external {
        require(balanceOf(msg.sender) >= shares, "Not enough ETF tokens");

        uint256 len = AssetsMap.size();
        IERC20 asset;
        uint256 amount;
        uint256 fees;

        for (uint256 i = 0; i < len; i++) {
            asset = IERC20(AssetsMap.getKeyAtIndex(i));
            amount = (asset.balanceOf(address(this)) * shares) / totalShares;

            fees = (amount * exitFee) / 1000;
            asset.transfer(owner(), fees);
            amount = amount - fees;

            asset.transfer(withdrawAddress, amount);
        }

        _burn(msg.sender, shares);

        totalShares = totalShares - shares;
    }

    function getTokenPrice(address _token, uint256 amount)
        internal
        view
        returns (uint256)
    {
        address[] memory path = new address[](3);

        path[0] = _token;
        path[1] = router.WETH();
        path[2] = address(token);

        uint256[] memory output = router.getAmountsOut(amount, path);

        return (output[output.length - 1]);
    }

    function getPrice()
        public
        view
        returns (uint256 unitPrice, uint256 totalPrice)
    {
        uint256 len = AssetsMap.size();
        address asset;

        for (uint256 i = 0; i < len; i++) {
            asset = AssetsMap.getKeyAtIndex(i);
            if (IERC20(asset).balanceOf(address(this)) > 0) {
                totalPrice += getTokenPrice(
                    asset,
                    IERC20(asset).balanceOf(address(this))
                );
            }
        }
        if (totalShares > 0) {
            unitPrice = totalPrice / totalShares;
        }
    }

    function swapTokenForAsset(address asset, uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(token);
        path[1] = router.WETH();
        path[2] = asset;

        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function setAllocation(address asset, uint256 allocation)
        external
        onlyOwner
    {
        uint256 oldValue = AssetsMap.get(asset);
        if (oldValue == 0) {
            IERC20(asset).approve(address(router), ~uint256(0));
        }
        AssetsMap.set(asset, allocation);

        if (allocation == 0) {
            AssetsMap.remove(asset);
        }

        totalAllocation = totalAllocation + allocation - oldValue;
    }

    function setFees(uint16 _entryFee, uint16 _exitFee) external onlyOwner {
        entryFee = _entryFee;
        exitFee = _exitFee;
    }

    function setToken(address newToken) external onlyOwner {
        token = IERC20(newToken);
        token.approve(address(router), ~uint256(0));
    }
}
