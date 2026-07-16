// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — DeFi · A constant-product AMM (YOUR TASK)
//
//  Complete the two functions that define the AMM's behaviour:
//    • getAmountOut  — the pricing formula  Δy = (rOut · Δx) / (rIn + Δx)
//    • swap          — pull tokens in, pay tokens out, enforce a slippage guard
//
//  Everything else (liquidity, shares, helpers) is provided. When done, verify
//  against the slide numbers: a 100 : 200 pool must return 1.98 for a swap of 1,
//  and 66.67 for a swap of 50. See the README.
// ─────────────────────────────────────────────────────────────────────────────

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title A tiny 18-decimals ERC-20 for the lab. Mints the full supply to the
///        deployer. NOT production code.
contract MinimalERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _initialSupply;
        balanceOf[msg.sender] = _initialSupply;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "ERC20: insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

/// @title Constant-product automated market maker (x · y = k), fee-free.
contract ConstantProductAMM {
    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    event Swap(address indexed who, address tokenIn, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed who, uint256 amount0, uint256 amount1, uint256 shares);
    event LiquidityRemoved(address indexed who, uint256 amount0, uint256 amount1, uint256 shares);

    constructor(address _token0, address _token1) {
        require(_token0 != _token1, "identical tokens");
        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    // ───────────── Pricing (pure) ─────────────

    /// @notice Output amount for a given input under x·y=k (no fee).
    /// @dev    TODO 1: implement the constant-product formula.
    ///           amountOut = (reserveOut * amountIn) / (reserveIn + amountIn)
    ///         Guard against amountIn == 0 and empty reserves first.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        // TODO 1: replace this stub.
        amountIn;
        reserveIn;
        reserveOut;
        amountOut = 0;
    }

    // ───────────── Swap ─────────────

    /// @notice Swap an exact `amountIn` of `tokenIn` for the other token.
    /// @dev    TODO 2: implement the swap. Steps:
    ///           1. require tokenIn is token0 or token1.
    ///           2. pick (tokenIn, tokenOut, reserveIn, reserveOut) accordingly.
    ///           3. amountOut = getAmountOut(amountIn, reserveIn, reserveOut).
    ///           4. require(amountOut >= minAmountOut)  // slippage guard.
    ///           5. token IN:  transferFrom(msg.sender, this, amountIn).
    ///           6. token OUT: transfer(msg.sender, amountOut).
    ///           7. call _sync() to refresh reserves; emit Swap.
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        // TODO 2: implement the swap.
        tokenIn;
        amountIn;
        minAmountOut;
        amountOut = 0;
    }

    // ───────────── Liquidity (provided) ─────────────

    function addLiquidity(uint256 amount0, uint256 amount1)
        external
        returns (uint256 shares)
    {
        require(token0.transferFrom(msg.sender, address(this), amount0), "pull0 failed");
        require(token1.transferFrom(msg.sender, address(this), amount1), "pull1 failed");

        if (totalShares == 0) {
            shares = _sqrt(amount0 * amount1);
        } else {
            uint256 s0 = (amount0 * totalShares) / reserve0;
            uint256 s1 = (amount1 * totalShares) / reserve1;
            shares = s0 < s1 ? s0 : s1;
        }
        require(shares > 0, "zero shares minted");

        sharesOf[msg.sender] += shares;
        totalShares += shares;

        _sync();
        emit LiquidityAdded(msg.sender, amount0, amount1, shares);
    }

    function removeLiquidity(uint256 shares)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(sharesOf[msg.sender] >= shares && shares > 0, "bad share amount");

        amount0 = (shares * reserve0) / totalShares;
        amount1 = (shares * reserve1) / totalShares;
        require(amount0 > 0 && amount1 > 0, "zero output");

        sharesOf[msg.sender] -= shares;
        totalShares -= shares;

        require(token0.transfer(msg.sender, amount0), "pay0 failed");
        require(token1.transfer(msg.sender, amount1), "pay1 failed");

        _sync();
        emit LiquidityRemoved(msg.sender, amount0, amount1, shares);
    }

    // ───────────── Views & helpers (provided) ─────────────

    function spotPrice0in1() external view returns (uint256) {
        require(reserve0 > 0, "no liquidity");
        return (reserve1 * 1e18) / reserve0;
    }

    function _sync() internal {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
