// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — DeFi · A constant-product AMM (the SOLUTION / reference)
//
//  A minimal Uniswap-V2-style liquidity pool for two ERC-20 tokens, holding the
//  product  k = reserve0 * reserve1  (approximately) constant across swaps.
//
//  This reference version is FEE-FREE on purpose, so its numbers match the
//  slide worked examples exactly:
//      pool 100 : 200   →   swap   1 in →  1.98 out
//                            swap  50 in → 66.67 out
//  (A real AMM charges ~0.30% per swap — that fee is what pays liquidity
//   providers. Adding it is the extension task at the bottom of the README.)
//
//  Two minimal ERC-20 tokens are included so the whole lab runs in the Remix
//  VM with no imports and no network.
//
//  PROVA RAPIDA (Remix VM, tutto dallo stesso account; importi a 18 decimali):
//   1) Deploy DUE token (contratto MinimalERC20), il costruttore vuole
//        name, symbol, supply. Usa supply = 1000000000000000000000000 (1.000.000):
//        - MinimalERC20("EtherToken","ETK", 1000000000000000000000000)
//        - MinimalERC20("UsdToken", "USDT",1000000000000000000000000)
//   2) Deploy ConstantProductAMM(<indirizzo ETK>, <indirizzo USDT>)   // token0=ETK, token1=USDT
//   3) APPROVA l'AMM su ENTRAMBI i token (serve prima di aggiungere liquidita'/swap):
//        su ETK  -> approve(<indirizzo AMM>, 1000000000000000000000000)
//        su USDT -> approve(<indirizzo AMM>, 1000000000000000000000000)
//   4) Sull'AMM: addLiquidity(100000000000000000000, 200000000000000000000)  // pool 100:200
//   5) Prezzo (funzione pure, tasto "call", nessuna tx):
//        getAmountOut(1000000000000000000, 100000000000000000000, 200000000000000000000)
//            -> 1980198019801980198   (~1.98)
//        getAmountOut(50000000000000000000, 100000000000000000000, 200000000000000000000)
//            -> 66666666666666666666  (~66.67)
//   6) Swap vero: swap(<indirizzo ETK>, 50000000000000000000, 0)  // vendi 50 ETK
//        -> ricevi ~66.67 USDT. Confronta spotPrice0in1() PRIMA e DOPO: il prezzo si sposta.
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
///        deployer. NOT production code (no access control, etc.).
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
    /// @dev    Δy = (reserveOut · Δx) / (reserveIn + Δx).
    ///         Notice: the bigger Δx is relative to reserveIn, the worse the
    ///         effective rate — that gap is SLIPPAGE, and it is why the pool
    ///         can never be fully drained.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        require(amountIn > 0, "insufficient input");
        require(reserveIn > 0 && reserveOut > 0, "no liquidity");
        amountOut = (reserveOut * amountIn) / (reserveIn + amountIn);
    }

    // ───────────── Swap ─────────────

    /// @notice Swap an exact `amountIn` of `tokenIn` for the other token.
    /// @param  minAmountOut slippage guard: revert if the output would be less.
    function swap(
        address tokenIn,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut) {
        require(
            tokenIn == address(token0) || tokenIn == address(token1),
            "unknown token"
        );
        bool zeroForOne = tokenIn == address(token0);

        (IERC20 tIn, IERC20 tOut, uint256 rIn, uint256 rOut) = zeroForOne
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        amountOut = getAmountOut(amountIn, rIn, rOut);
        require(amountOut >= minAmountOut, "slippage: too little out");

        require(tIn.transferFrom(msg.sender, address(this), amountIn), "pull failed");
        require(tOut.transfer(msg.sender, amountOut), "pay failed");

        _sync();
        emit Swap(msg.sender, tokenIn, amountIn, amountOut);
    }

    // ───────────── Liquidity ─────────────

    /// @notice Provide liquidity and receive pool shares.
    /// @dev    First provider sets the price and mints sqrt(a0·a1) shares.
    ///         Later providers mint pro-rata to whichever side they under-supply.
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

    /// @notice Burn shares and withdraw the proportional reserves.
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

    // ───────────── Views & helpers ─────────────

    /// @notice Spot price of token0 in units of token1 (reserve ratio),
    ///         scaled by 1e18. This is exactly the AMM spot price you must
    ///         NEVER feed directly into another protocol's state-changing
    ///         logic — one large (flash-loaned) swap moves it at will.
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
