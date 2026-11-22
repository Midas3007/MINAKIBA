// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @title MINAKIBA FundVault
/// @notice A private USDC pool on Base. Approved members queue deposits and redemptions; the operator settles the
///         queue once a day at one price, `nav / supply`. Shares are non-transferable. The trading money sits in the
///         treasury wallet (Kiyoshi's wallet); this contract only holds queued deposits and unclaimed payouts.
/// @dev    No upgradeability. The only external contract it calls is USDC.
///         Units: USDC has 6 decimals, shares have 18. "price" = USDC units per 1e18 shares (1e6 = $1.00).
contract FundVault {
    // ---------------------------------------------------------------- share token (non-transferable)
    string public constant name = "MINAKIBA Share";
    string public constant symbol = "MNKB";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error NonTransferable();

    function transfer(address, uint256) external pure returns (bool) { revert NonTransferable(); }
    function transferFrom(address, address, uint256) external pure returns (bool) { revert NonTransferable(); }
    function approve(address, uint256) external pure returns (bool) { revert NonTransferable(); }
    function allowance(address, address) external pure returns (uint256) { return 0; }

    // ---------------------------------------------------------------- constants
    uint256 public constant FEE_CAP_BPS = 2000;          // 20%
    uint256 public constant DELAY = 48 hours;            // every role / fee / limit change waits this long
    uint256 public constant QUEUE_LIMIT = 100;           // per side, keeps settle() within gas
    uint256 public constant WINDOW = 1 days;             // value-jump guard window
    uint256 private constant ONE_SHARE = 1e18;
    uint256 private constant UNIT_SCALE = 1e12;          // 1 USDC unit -> 1e12 share units at $1.00

    IERC20 public immutable usdc;

    // ---------------------------------------------------------------- roles and settings
    address public owner;          // hardware wallet or Safe; never the bot wallet
    address public operator;       // keeper wallet: reports value and settles; holds gas only
    address public manager;
    address public feeRecipient;
    address public treasury;       // Kiyoshi's wallet: holds the trading money

    uint256 public feeBps;
    uint256 public maxNavChangeBps;
    uint256 public minDeposit;      // USDC units
    uint256 public maxPerMember;    // USDC units of cost basis + queued deposits per member (0 = no limit)
    uint256 public maxTotal;        // USDC units of fund value + queued deposits (0 = no limit)

    bool public paused;
    bool public pausedByOwner;
    bool public openingDone;

    mapping(address => bool) public allowed;

    // ---------------------------------------------------------------- accounting
    uint256 public lastNav;             // treasury value after the latest report / settlement (USDC units)
    uint256 public lastPrice = 1e6;     // USDC units per share
    uint256 public windowStart;         // value-jump guard
    uint256 public windowPrice;

    mapping(address => uint256) public costBasis;   // USDC put in, reduced pro rata on redemption
    mapping(address => uint256) public feesPaid;    // realized performance fees, USDC units

    mapping(address => uint256) public pendingDeposit;   // USDC waiting in this contract
    mapping(address => uint256) public pendingRedeem;    // shares waiting in escrow (held by this contract)
    mapping(address => uint256) public claimable;        // USDC payouts that could not be sent
    uint256 public totalPendingDeposits;
    uint256 public totalPendingRedeem;
    uint256 public totalClaimable;

    address[] internal depositQueue;
    address[] internal redeemQueue;
    mapping(address => uint256) internal depositPos;     // index + 1
    mapping(address => uint256) internal redeemPos;

    // ---------------------------------------------------------------- delayed changes
    enum Kind { Owner, Operator, Manager, FeeRecipient, Fee, MaxNavChange, Treasury }
    struct Change { Kind kind; uint256 value; uint64 eta; uint8 status; } // status: 1 queued, 2 cancelled, 3 executed
    Change[] public changes;

    // ---------------------------------------------------------------- events
    event DepositRequested(address indexed member, uint256 assets);
    event DepositCancelled(address indexed member, uint256 assets);
    event Deposited(address indexed member, uint256 assets, uint256 shares);
    event RedeemRequested(address indexed member, uint256 shares);
    event RedeemCancelled(address indexed member, uint256 shares);
    event Redeemed(address indexed member, uint256 shares, uint256 gross, uint256 fee, uint256 paid);
    event PayoutDeferred(address indexed member, uint256 amount);
    event Claimed(address indexed member, uint256 amount);
    event ValueReported(uint256 nav, uint256 supply, uint256 price);
    event Settled(uint256 nav, uint256 supply, uint256 price, uint256 nairaRate, uint256 deposits, uint256 payouts, uint256 navAfter, uint256 supplyAfter);
    event ChangeQueued(uint256 indexed id, Kind kind, uint256 value, uint256 eta, address by);
    event ChangeCancelled(uint256 indexed id, address by);
    event ChangeExecuted(uint256 indexed id, Kind kind, uint256 value);
    event Paused(address by);
    event Unpaused(address by);
    event Allowed(address indexed member, bool allowed);
    event LimitsSet(uint256 minDeposit, uint256 maxPerMember, uint256 maxTotal);
    event OpeningShares(address indexed to, uint256 assets, uint256 shares);

    // ---------------------------------------------------------------- errors
    error NotAllowed();
    error Unauthorized();
    error IsPaused();
    error BadAmount();
    error OverLimit();
    error QueueFull();
    error NothingQueued();
    error ValueJump();
    error NoValue();
    error TooEarly();
    error BadChange();
    error FeeTooHigh();
    error ZeroAddress();
    error TransferFailed();
    error Reentrant();

    uint256 private locked = 1;
    modifier nonReentrant() { if (locked != 1) revert Reentrant(); locked = 2; _; locked = 1; }
    modifier only(address a) { if (msg.sender != a) revert Unauthorized(); _; }
    modifier ownerOrManager() { if (msg.sender != owner && msg.sender != manager) revert Unauthorized(); _; }
    modifier notPaused() { if (paused) revert IsPaused(); _; }

    constructor(
        address usdc_, address owner_, address operator_, address manager_, address feeRecipient_, address treasury_,
        uint256 feeBps_, uint256 minDeposit_, uint256 maxPerMember_, uint256 maxTotal_
    ) {
        if (usdc_ == address(0) || owner_ == address(0) || operator_ == address(0) || manager_ == address(0)
            || feeRecipient_ == address(0) || treasury_ == address(0)) revert ZeroAddress();
        if (owner_ == treasury_ || operator_ == treasury_) revert NotAllowed();   // owner is never the bot wallet
        if (feeBps_ > FEE_CAP_BPS) revert FeeTooHigh();
        usdc = IERC20(usdc_);
        owner = owner_; operator = operator_; manager = manager_; feeRecipient = feeRecipient_; treasury = treasury_;
        feeBps = feeBps_;
        maxNavChangeBps = 2500;
        minDeposit = minDeposit_; maxPerMember = maxPerMember_; maxTotal = maxTotal_;
        windowStart = block.timestamp; windowPrice = 1e6;
        emit LimitsSet(minDeposit_, maxPerMember_, maxTotal_);
    }

    // ================================================================ members
    function requestDeposit(uint256 assets) external nonReentrant notPaused {
        if (!allowed[msg.sender]) revert NotAllowed();
        if (assets == 0 || assets < minDeposit) revert BadAmount();
        if (maxPerMember != 0 && costBasis[msg.sender] + pendingDeposit[msg.sender] + assets > maxPerMember) revert OverLimit();
        if (maxTotal != 0 && lastNav + totalPendingDeposits + assets > maxTotal) revert OverLimit();
        if (depositPos[msg.sender] == 0) {
            if (depositQueue.length >= QUEUE_LIMIT) revert QueueFull();
            depositQueue.push(msg.sender); depositPos[msg.sender] = depositQueue.length;
        }
        pendingDeposit[msg.sender] += assets;
        totalPendingDeposits += assets;
        _pull(msg.sender, address(this), assets);
        emit DepositRequested(msg.sender, assets);
    }

    /// @notice Works while paused.
    function cancelDeposit() external nonReentrant {
        uint256 assets = pendingDeposit[msg.sender];
        if (assets == 0) revert NothingQueued();
        _dropDeposit(msg.sender);
        _send(msg.sender, assets);
        emit DepositCancelled(msg.sender, assets);
    }

    function requestRedeem(uint256 shares) external nonReentrant notPaused {
        if (shares == 0 || shares > balanceOf[msg.sender]) revert BadAmount();
        if (redeemPos[msg.sender] == 0) {
            if (redeemQueue.length >= QUEUE_LIMIT) revert QueueFull();
            redeemQueue.push(msg.sender); redeemPos[msg.sender] = redeemQueue.length;
        }
        _move(msg.sender, address(this), shares);
        pendingRedeem[msg.sender] += shares;
        totalPendingRedeem += shares;
        emit RedeemRequested(msg.sender, shares);
    }

    /// @notice Works while paused.
    function cancelRedeem() external nonReentrant {
        uint256 shares = pendingRedeem[msg.sender];
        if (shares == 0) revert NothingQueued();
        _dropRedeem(msg.sender);
        _move(address(this), msg.sender, shares);
        emit RedeemCancelled(msg.sender, shares);
    }

    /// @notice Collect a payout that could not be sent at settlement. Works while paused.
    function claim() external nonReentrant {
        uint256 amount = claimable[msg.sender];
        if (amount == 0) revert NothingQueued();
        claimable[msg.sender] = 0;
        totalClaimable -= amount;
        _send(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // ================================================================ operator
    /// @notice Hourly value report: the treasury's value in USDC units, with the costs pot already taken out.
    function reportValue(uint256 nav) external only(operator) notPaused {
        uint256 supply = totalSupply;
        if (supply == 0) { lastNav = nav; emit ValueReported(nav, 0, lastPrice); return; }
        uint256 price = nav * ONE_SHARE / supply;
        _guard(price);
        lastNav = nav; lastPrice = price;
        emit ValueReported(nav, supply, price);
    }

    /// @notice Daily settlement. Every queued redemption and deposit is priced at `nav / supply`, redemptions first.
    ///         Deposits pay the redemptions; the treasury tops up or receives the difference.
    /// @param nav        treasury value in USDC units, pot excluded, before this settlement's flows
    /// @param nairaRate  the fund naira rate (NGN per $1, 6 decimals), stored so naira values can be recomputed
    function settle(uint256 nav, uint256 nairaRate) external only(operator) notPaused nonReentrant {
        uint256 supply = totalSupply;
        uint256 price;
        if (supply == 0) {
            price = 1e6;
        } else {
            if (nav == 0) revert NoValue();
            price = nav * ONE_SHARE / supply;
            _guard(price);
        }

        // ---- redemptions
        uint256 payouts;
        address[] memory payees = new address[](redeemQueue.length);
        uint256[] memory amounts = new uint256[](redeemQueue.length);
        for (uint256 i = 0; i < redeemQueue.length; i++) {
            address m = redeemQueue[i];
            uint256 s = pendingRedeem[m];
            uint256 gross = s * nav / supply;
            uint256 held = balanceOf[m] + s;
            uint256 costPart = costBasis[m] * s / held;
            uint256 fee;
            if (m != feeRecipient && gross > costPart) fee = (gross - costPart) * feeBps / 10_000;
            uint256 feeShares = fee * supply / nav;
            uint256 paid = gross - fee;

            costBasis[m] -= costPart;
            pendingRedeem[m] = 0;
            redeemPos[m] = 0;
            if (feeShares > 0) {
                _move(address(this), feeRecipient, feeShares);
                costBasis[feeRecipient] += fee;
                feesPaid[m] += fee;
            }
            _burn(address(this), s - feeShares);
            payees[i] = m; amounts[i] = paid;
            payouts += paid;
            emit Redeemed(m, s, gross, fee, paid);
        }
        delete redeemQueue;
        totalPendingRedeem = 0;

        // ---- deposits, same price
        uint256 deposits;
        for (uint256 i = 0; i < depositQueue.length; i++) {
            address m = depositQueue[i];
            uint256 a = pendingDeposit[m];
            uint256 shares = supply == 0 ? a * UNIT_SCALE : a * supply / nav;
            pendingDeposit[m] = 0;
            depositPos[m] = 0;
            costBasis[m] += a;
            _mint(m, shares);
            deposits += a;
            emit Deposited(m, a, shares);
        }
        delete depositQueue;
        totalPendingDeposits = 0;

        // ---- net against the treasury
        if (payouts > deposits) _pull(treasury, address(this), payouts - deposits);
        else if (deposits > payouts) _send(treasury, deposits - payouts);
        for (uint256 i = 0; i < payees.length; i++) {
            if (amounts[i] == 0) continue;
            if (!_trySend(payees[i], amounts[i])) {
                claimable[payees[i]] += amounts[i];
                totalClaimable += amounts[i];
                emit PayoutDeferred(payees[i], amounts[i]);
            }
        }

        uint256 navAfter = nav + deposits - payouts;
        lastNav = navAfter;
        lastPrice = price;
        emit Settled(nav, supply, price, nairaRate, deposits, payouts, navAfter, totalSupply);
    }

    // ================================================================ manager / owner (immediate, cannot move money)
    function pause() external ownerOrManager {
        paused = true;
        if (msg.sender == owner) pausedByOwner = true;
        emit Paused(msg.sender);
    }

    /// @notice A pause by the owner can only be lifted by the owner.
    function unpause() external ownerOrManager {
        if (pausedByOwner && msg.sender != owner) revert Unauthorized();
        paused = false; pausedByOwner = false;
        emit Unpaused(msg.sender);
    }

    function setAllowed(address member, bool ok) external ownerOrManager {
        allowed[member] = ok;
        emit Allowed(member, ok);
    }

    function setLimits(uint256 minDeposit_, uint256 maxPerMember_, uint256 maxTotal_) external ownerOrManager {
        minDeposit = minDeposit_; maxPerMember = maxPerMember_; maxTotal = maxTotal_;
        emit LimitsSet(minDeposit_, maxPerMember_, maxTotal_);
    }

    /// @notice One time, before anyone else holds shares: shares at $1.00 for value already in the treasury.
    function openingShares(address to, uint256 assets) external ownerOrManager {
        if (openingDone || totalSupply != 0) revert NotAllowed();
        if (to == address(0) || assets == 0) revert BadAmount();
        openingDone = true;
        uint256 shares = assets * UNIT_SCALE;
        costBasis[to] += assets;
        lastNav = assets; lastPrice = 1e6;
        windowStart = block.timestamp; windowPrice = 1e6;
        _mint(to, shares);
        emit OpeningShares(to, assets, shares);
    }

    // ================================================================ delayed changes (48 hours)
    /// @notice Fee: manager only. Everything else: owner only. Anyone can execute after the delay.
    function queueChange(Kind kind, uint256 value) external returns (uint256 id) {
        if (kind == Kind.Fee) {
            if (msg.sender != manager) revert Unauthorized();
            if (value > FEE_CAP_BPS) revert FeeTooHigh();
        } else {
            if (msg.sender != owner) revert Unauthorized();
            if (kind == Kind.MaxNavChange) { if (value == 0 || value > 10_000) revert BadChange(); }
            else if (value == 0 || value > type(uint160).max) revert BadChange();
        }
        if ((kind == Kind.Owner || kind == Kind.Operator) && address(uint160(value)) == treasury) revert BadChange();
        if (kind == Kind.Treasury && address(uint160(value)) == owner) revert BadChange();
        id = changes.length;
        uint64 eta = uint64(block.timestamp + DELAY);
        changes.push(Change(kind, value, eta, 1));
        emit ChangeQueued(id, kind, value, eta, msg.sender);
    }

    function cancelChange(uint256 id) external ownerOrManager {
        Change storage c = changes[id];
        if (c.status != 1) revert BadChange();
        c.status = 2;
        emit ChangeCancelled(id, msg.sender);
    }

    function executeChange(uint256 id) external {
        Change storage c = changes[id];
        if (c.status != 1) revert BadChange();
        if (block.timestamp < c.eta) revert TooEarly();
        c.status = 3;
        address a = address(uint160(c.value));
        if (c.kind == Kind.Owner) { if (a == treasury) revert BadChange(); owner = a; }
        else if (c.kind == Kind.Operator) { if (a == treasury) revert BadChange(); operator = a; }
        else if (c.kind == Kind.Manager) manager = a;
        else if (c.kind == Kind.FeeRecipient) feeRecipient = a;
        else if (c.kind == Kind.Fee) { if (c.value > FEE_CAP_BPS) revert FeeTooHigh(); feeBps = c.value; }
        else if (c.kind == Kind.MaxNavChange) maxNavChangeBps = c.value;
        else if (c.kind == Kind.Treasury) { if (a == owner || a == operator) revert BadChange(); treasury = a; }
        emit ChangeExecuted(id, c.kind, c.value);
    }

    // ================================================================ views
    function changeCount() external view returns (uint256) { return changes.length; }
    function depositQueueLength() external view returns (uint256) { return depositQueue.length; }
    function redeemQueueLength() external view returns (uint256) { return redeemQueue.length; }
    function depositQueueAt(uint256 i) external view returns (address) { return depositQueue[i]; }
    function redeemQueueAt(uint256 i) external view returns (address) { return redeemQueue[i]; }

    /// @notice Shares a member holds, including shares waiting in the redemption queue.
    function sharesOf(address m) external view returns (uint256) { return balanceOf[m] + pendingRedeem[m]; }

    // ================================================================ internals
    function _guard(uint256 price) internal {
        if (block.timestamp >= windowStart + WINDOW) { windowStart = block.timestamp; windowPrice = lastPrice; }
        uint256 ref = windowPrice;
        uint256 diff = price > ref ? price - ref : ref - price;
        if (diff * 10_000 > ref * maxNavChangeBps) revert ValueJump();
    }

    function _mint(address to, uint256 v) internal { totalSupply += v; balanceOf[to] += v; emit Transfer(address(0), to, v); }
    function _burn(address from, uint256 v) internal { balanceOf[from] -= v; totalSupply -= v; emit Transfer(from, address(0), v); }
    function _move(address from, address to, uint256 v) internal { balanceOf[from] -= v; balanceOf[to] += v; emit Transfer(from, to, v); }

    function _dropDeposit(address m) internal {
        totalPendingDeposits -= pendingDeposit[m];
        pendingDeposit[m] = 0;
        uint256 i = depositPos[m] - 1;
        address last = depositQueue[depositQueue.length - 1];
        depositQueue[i] = last; depositPos[last] = i + 1;
        depositQueue.pop(); depositPos[m] = 0;
    }

    function _dropRedeem(address m) internal {
        totalPendingRedeem -= pendingRedeem[m];
        pendingRedeem[m] = 0;
        uint256 i = redeemPos[m] - 1;
        address last = redeemQueue[redeemQueue.length - 1];
        redeemQueue[i] = last; redeemPos[last] = i + 1;
        redeemQueue.pop(); redeemPos[m] = 0;
    }

    function _pull(address from, address to, uint256 v) internal {
        (bool ok, bytes memory r) = address(usdc).call(abi.encodeCall(IERC20.transferFrom, (from, to, v)));
        if (!ok || (r.length != 0 && !abi.decode(r, (bool)))) revert TransferFailed();
    }

    function _send(address to, uint256 v) internal { if (!_trySend(to, v)) revert TransferFailed(); }

    function _trySend(address to, uint256 v) internal returns (bool) {
        (bool ok, bytes memory r) = address(usdc).call(abi.encodeCall(IERC20.transfer, (to, v)));
        return ok && (r.length == 0 || abi.decode(r, (bool)));
    }
}
