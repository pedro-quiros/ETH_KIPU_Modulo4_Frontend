// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

using SafeERC20 for IERC20;

contract SimpleSwap is ERC20 {
    uint constant DECIMALS_FACTOR = 10**18;
    uint constant MINIMUM_LIQUIDITY = 0;
    bool private locked;

    struct TokenPairData {
        address tokenA;
        address tokenB;
        uint reserveA;
        uint reserveB;
        uint amountA;
        uint amountB;
        uint amountADesired;
        uint amountBDesired;
        uint amountAMin;
        uint amountBMin;
        bool reversed;
    }

    mapping(address => mapping(address => uint)) public reserve;

    constructor() ERC20("Liquidity Token", "LTK") {}

    modifier nonReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    modifier isNotExpired(uint deadline) {
        require(block.timestamp <= deadline, "Transaction expired");
        _;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        external
        nonReentrant
        isNotExpired(deadline)
        returns (uint amountA, uint amountB, uint liquidity)
    {
        require(amountADesired >= amountAMin, "amountADesired too low");
        require(amountBDesired >= amountBMin, "amountBDesired too low");

        TokenPairData memory data = reorderTokens(tokenA, tokenB);
        data.amountADesired = data.reversed ? amountBDesired : amountADesired;
        data.amountBDesired = data.reversed ? amountADesired : amountBDesired;
        data.amountAMin = data.reversed ? amountBMin : amountAMin;
        data.amountBMin = data.reversed ? amountAMin : amountBMin;

        bool isInitialLiquidity = false;

        require(
            (data.reserveA == 0 && data.reserveB == 0) || (data.reserveA > 0 && data.reserveB > 0),
            "Invalid reserve state"
        );

        if (data.reserveA == 0 && data.reserveB == 0) {
            data.amountA = data.amountADesired; 
            data.amountB = data.amountBDesired; 
            isInitialLiquidity = true;
            liquidity = calculateInitialLiquidity(data);
        } else {
            data.amountB = data.amountBDesired;
            data.amountA = (data.amountBDesired * data.reserveA) / data.reserveB;

            if (data.amountA < data.amountAMin || data.amountA > data.amountADesired) {
                data.amountA = data.amountADesired;
                data.amountB = (data.amountADesired * data.reserveB) / data.reserveA;

                require(
                    data.amountB >= amountBMin && data.amountB <= data.amountBDesired,
                    "Amounts do not meet constraints"
                );
            }

            liquidity = calculateExistingLiquidity(data);
        }

        addLiquidityTransact(msg.sender, to, data, liquidity, isInitialLiquidity);

        amountA = data.reversed ? data.amountB : data.amountA;
        amountB = data.reversed ? data.amountA : data.amountB;
    }

    function addLiquidityTransact(
        address from,
        address to,
        TokenPairData memory data,
        uint liquidity,
        bool isInitialLiquidity
    ) internal {
        IERC20(data.tokenA).safeTransferFrom(from, address(this), data.amountA);
        IERC20(data.tokenB).safeTransferFrom(from, address(this), data.amountB);

        _mint(to, liquidity);

        if (isInitialLiquidity) {
            _mint(address(this), MINIMUM_LIQUIDITY);
        }

        reserve[data.tokenA][data.tokenB] += data.amountA;
        reserve[data.tokenB][data.tokenA] += data.amountB;

        emit LiquidityAdded(from, to, data.tokenA, data.tokenB, data.amountA, data.amountB, liquidity);
    }

    event LiquidityAdded(address indexed from, address indexed to, address tokenA, address tokenB, uint amountA, uint amountB, uint liquidity);    

    function calculateInitialLiquidity(TokenPairData memory data) internal pure returns (uint liquidity) {
        liquidity = sqrt(data.amountA * data.amountB) - MINIMUM_LIQUIDITY;
        require(liquidity > 0, "Liquidity too low");
    }

    function calculateExistingLiquidity(TokenPairData memory data) internal view returns (uint liquidity) {
        uint256 totalSupplyLTK = totalSupply();
        uint256 liquidityA = (data.amountA * totalSupplyLTK) / data.reserveA;
        uint256 liquidityB = (data.amountB * totalSupplyLTK) / data.reserveB;
        liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    )
        external
        nonReentrant
        isNotExpired(deadline)
        returns (uint amountA, uint amountB)
    {
        require(liquidity > 0, "Zero liquidity");

        TokenPairData memory data = reorderTokens(tokenA, tokenB);

        data.amountAMin = data.reversed ? amountBMin : amountAMin;
        data.amountBMin = data.reversed ? amountAMin : amountBMin;

        uint256 totalSupplyLTK = totalSupply();
        data.amountA = (liquidity * data.reserveA) / totalSupplyLTK;
        data.amountB = (liquidity * data.reserveB) / totalSupplyLTK;

        require(data.amountA >= data.amountAMin, "amountA too low");
        require(data.amountB >= data.amountBMin, "amountB too low");

        _burn(msg.sender, liquidity);

        IERC20(data.tokenA).safeTransfer(to, data.amountA);
        IERC20(data.tokenB).safeTransfer(to, data.amountB);

        reserve[data.tokenA][data.tokenB] -= data.amountA;
        reserve[data.tokenB][data.tokenA] -= data.amountB;

        amountA = data.reversed ? data.amountB : data.amountA;
        amountB = data.reversed ? data.amountA : data.amountB;

        emit LiquidityRemoved(msg.sender, to, liquidity, data.tokenA, data.tokenB, amountA, amountB);
    }

    event LiquidityRemoved(address indexed from, address indexed to, uint256 liquidity, address tokenA, address tokenB, uint256 amountA, uint256 amountB);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        nonReentrant
        isNotExpired(deadline)
        returns (uint[] memory amounts)
    {
        require(amountIn > 0, "Zero amountIn");
        require(amountOutMin > 0, "Zero amountOutMin");
        require(path.length == 2, "Only 1-pair swaps allowed");

        uint amountOut;
        TokenPairData memory data = reorderTokens(path[0], path[1]);

        require(data.reserveA > 0 && data.reserveB > 0, "Empty reserves");

        if (data.reversed) {
            amountOut = (amountIn * data.reserveA) / (data.reserveB + amountIn);
            data.amountA = amountOut;
            data.amountB = amountIn;            
        } else {            
            amountOut = (amountIn * data.reserveB) / (data.reserveA + amountIn);
            data.amountA = amountIn;
            data.amountB = amountOut;
        }

        require(data.amountB >= amountOutMin, "Slippage exceeded");

        swapExactTokensForTokensTransact(data, msg.sender, to);

        amounts = new uint[](path.length);
        amounts[0] = data.reversed ? data.amountB : data.amountA;
        amounts[1] = data.reversed ? data.amountA : data.amountB;

        emit SwapExecuted(msg.sender, to, path, amounts);
    }

    function reorderTokens(address tokenA, address tokenB) internal view returns (TokenPairData memory data) {
        require(tokenA != tokenB, "Tokens must differ");
        data.reversed = tokenA > tokenB;
        data.tokenA = data.reversed ? tokenB : tokenA; 
        data.tokenB = data.reversed ? tokenA : tokenB; 
        data.reserveA = reserve[data.tokenA][data.tokenB];
        data.reserveB = reserve[data.tokenB][data.tokenA];
    }

    function swapExactTokensForTokensTransact(
        TokenPairData memory data,
        address from,
        address to
    ) internal {
        if (data.reversed) {
            IERC20(data.tokenA).safeTransfer(to, data.amountA);
            IERC20(data.tokenB).safeTransferFrom(from, address(this), data.amountB);
            reserve[data.tokenA][data.tokenB] -= data.amountB;
            reserve[data.tokenB][data.tokenA] += data.amountA;
        } else {
            IERC20(data.tokenA).safeTransferFrom(from, address(this), data.amountA);
            IERC20(data.tokenB).safeTransfer(to, data.amountB);
            reserve[data.tokenA][data.tokenB] += data.amountA;
            reserve[data.tokenB][data.tokenA] -= data.amountB;
        }            
    }

    event SwapExecuted(address indexed from, address indexed to, address[] path, uint[] amounts);

    function getPrice(address tokenA, address tokenB) public view returns (uint price) {
        uint reserveA = reserve[tokenA][tokenB];
        uint reserveB = reserve[tokenB][tokenA];
        require(reserveA > 0 && reserveB > 0, "Insufficient reserves");
        return (reserveB * DECIMALS_FACTOR) / reserveA;
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut) {
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0 || x == 1) return x;
        uint256 z = (x / 2) + 1;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}