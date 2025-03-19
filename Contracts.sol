// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LendingContract is ReentrancyGuard {
    // Constants
    uint256 public constant LIQUIDATION_THRESHOLD = 150; // 150% (collateral value must be at least 1.5x the loan value)
    uint256 public constant LTV_RATIO = 70; // 70% loan-to-value ratio
    
    // State variables
    IERC20 public usdt;
    IERC20 public wbtc;
    uint256 public btcPrice;
    address public owner;

    struct Loan {
        uint256 btcCollateral;
        uint256 usdtLoan;
        uint256 timestamp;
        bool isActive;
    }

    // Mapping of user address to their loan details
    mapping(address => Loan) public loans;

    // Events
    event LoanCreated(address indexed user, uint256 btcCollateral, uint256 usdtLoan);
    event Liquidated(address indexed user, uint256 btcCollateral, uint256 usdtLoan);
    event CollateralAdded(address indexed user, uint256 amount);
    event LoanRepaid(address indexed borrower, uint256 amount, bool isUsdt);
    event LoanIssued(address indexed user, uint256 btcCollateral, uint256 usdtLoan);
    event CollateralReturned(address indexed borrower, uint256 amount);
    event PriceUpdated(uint256 newPrice);

    constructor(address _usdt, address _wbtc) {
        owner = msg.sender;
        usdt = IERC20(_usdt);
        wbtc = IERC20(_wbtc);
        btcPrice = 50000 * 1e6; // Initial BTC price in USDT (example: $50,000)
    }   

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }   

    // Function to liquidate a loan if collateral falls below threshold
    function liquidate(address _user) external onlyOwner nonReentrant {
        require(_user != address(0), "Invalid address");
        require(loans[_user].isActive, "Loan is not active");

        uint256 loanValue = loans[_user].usdtLoan;
        require(loanValue > 0, "No active loan to liquidate");

        uint256 collateralValue = (loans[_user].btcCollateral * btcPrice) / 1e8;

        // Check if liquidation threshold is breached (collateral value should be BELOW the threshold)
        require(
            (collateralValue * 100) / loanValue < LIQUIDATION_THRESHOLD,
            "Liquidation threshold not reached"
        );

        uint256 collateralAmount = loans[_user].btcCollateral;
        
        // Mark loan as inactive BEFORE external calls (prevent reentrancy)
        loans[_user].isActive = false;

        // Transfer collateral to owner as part of liquidation
        require(
            wbtc.transfer(owner, collateralAmount),
            "Collateral transfer failed"
        );

        emit Liquidated(_user, collateralAmount, loanValue);
    }

    function updateBtcPrice(uint256 _btcPrice) external onlyOwner {
        require(_btcPrice > 0, "BTC price must be greater than 0");
        btcPrice = _btcPrice;
        emit PriceUpdated(_btcPrice);
    }

    // Function to get loan details for a user
    function getLoanDetails(address _user)
        external
        view
        returns (
            uint256 btcCollateral,
            uint256 usdtLoan,
            uint256 timestamp,
            bool isActive
        )
    {
        Loan memory loan = loans[_user];
        return (
            loan.btcCollateral,
            loan.usdtLoan,
            loan.timestamp,
            loan.isActive
        );
    }

    // Function to check if a loan is eligible for liquidation
    function isLiquidatable(address _user) external view returns (bool) {
        if (!loans[_user].isActive) return false;
        
        uint256 loanValue = loans[_user].usdtLoan;
        if (loanValue == 0) return false;
        
        uint256 collateralValue = (loans[_user].btcCollateral * btcPrice) / 1e8;
        return (collateralValue * 100) / loanValue < LIQUIDATION_THRESHOLD;
    }

    function acceptWBTC(address _to,uint256 _amount) public {
        require(wbtc.transferFrom(msg.sender,_to,_amount));
        
    }

    function acceptUSDT(address _to,uint256 _amount) public {
        require(usdt.transferFrom(msg.sender, _to, _amount));
    }

    // Dummy function to create a loan (for testing purposes)
    // function createLoan(uint256 _btcCollateral, uint256 _usdtLoan) external {
    //     loans[msg.sender] = Loan({
    //         btcCollateral: _btcCollateral,
    //         usdtLoan: _usdtLoan,
    //         timestamp: block.timestamp,
    //         isActive: true
    //     });

    //     emit LoanCreated(msg.sender, _btcCollateral, _usdtLoan);
    // }
    function createLoan(uint256 _btcCollateral) external {
        // Calculate USDT loan amount (70 USDT per 1 WBTC)
        uint256 _usdtLoan = _btcCollateral * 70;
        
        // Transfer WBTC from user to contract as collateral
        require(wbtc.transferFrom(msg.sender, address(this), _btcCollateral), "WBTC transfer failed");
        
        // Transfer USDT from contract to user as loan
        require(usdt.transfer(msg.sender, _usdtLoan), "USDT transfer failed");
        
        // Record the loan details
        loans[msg.sender] = Loan({
            btcCollateral: _btcCollateral,
            usdtLoan: _usdtLoan,
            timestamp: block.timestamp,
            isActive: true
        });
        
        emit LoanCreated(msg.sender, _btcCollateral, _usdtLoan);
    }

    function loanRepayment(uint256 repaymentAmount, bool isUsdt) external nonReentrant {
        require(loans[msg.sender].isActive, "No active loan");
        require(
            repaymentAmount >= loans[msg.sender].usdtLoan,
            "Repayment amount insufficient"
        );
        
        uint256 collateralToReturn = loans[msg.sender].btcCollateral;
        uint256 loanAmount = loans[msg.sender].usdtLoan;
        
        // Prevent reentrancy by marking loan inactive BEFORE external calls
        loans[msg.sender].isActive = false;
        
        if (isUsdt) {
            // Check allowance first (prevents unnecessary reverts)
            require(
                usdt.allowance(msg.sender, address(this)) >= repaymentAmount,
                "USDT allowance too low"
            );
            require(
                usdt.transferFrom(msg.sender, address(this), repaymentAmount),
                "USDT transfer failed"
            );
        } else {
            // Convert loan amount to WBTC based on BTC price
            uint256 wbtcAmount = (loanAmount * 1e8) / btcPrice;
            require(
                wbtc.allowance(msg.sender, address(this)) >= wbtcAmount,
                "WBTC allowance too low"
            );
            require(
                wbtc.transferFrom(msg.sender, address(this), wbtcAmount),
                "WBTC transfer failed"
            );
        }
        
        // Return BTC collateral to borrower
        // require(
        //     wbtc.transfer(msg.sender, collateralToReturn),
        //     "Collateral return failed"
        // );
        
        emit LoanRepaid(msg.sender, repaymentAmount, isUsdt);
        emit CollateralReturned(msg.sender, collateralToReturn);
    }

    function lockBtcAndGetLoan(uint256 _btcCollateral) external nonReentrant {
        require(_btcCollateral > 0, "BTC Collateral must be greater than 0");
        require(!loans[msg.sender].isActive, "Loan already active");
        require(btcPrice > 0, "BTC price not set");
        
        // Check if user has approved the contract to spend their WBTC
        require(
            wbtc.allowance(msg.sender, address(this)) >= _btcCollateral,
            "WBTC allowance too low"
        );
        
        // Calculate loan amount (70% of collateral value)
        uint256 usdtLoanAmount = ((_btcCollateral * btcPrice) / 1e8) * LTV_RATIO / 100;
        
        // Ensure contract has enough USDT to issue the loan
        require(
            usdt.balanceOf(address(this)) >= usdtLoanAmount,
            "Contract does not have enough USDT"
        );
        
        // Transfer collateral from user to contract
        require(
            wbtc.transferFrom(msg.sender, address(this), _btcCollateral),
            "Failed to transfer BTC collateral"
        );
        
        // Create the loan record
        loans[msg.sender] = Loan({
            btcCollateral: _btcCollateral,
            usdtLoan: usdtLoanAmount,
            timestamp: block.timestamp,
            isActive: true
        });
        
        // Transfer USDT loan to borrower
        require(
            usdt.transfer(msg.sender, usdtLoanAmount),
            "Failed to transfer USDT loan"
        );

        emit LoanIssued(msg.sender, _btcCollateral, usdtLoanAmount);
    }
}
