// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract LendingContract {
    // Constants
    uint256 public constant LIQUIDATION_THRESHOLD = 150; // 150% (collateral value must be at least 1.5x the loan value)
    IERC20 public usdt;
    IERC20 public wbtc;
    uint256 public btcPrice;
    uint256 public constant LTV_RATIO = 70;
    address public owner;

    struct Loan {
        uint256 btcCollateral;
        uint256 usdtLoan;
        uint256 timestamp;
        bool isActive;
    }

    constructor(){
        owner = msg.sender;
    }   

    modifier onlyOwner(){
        require(msg.sender==owner,"Only owner can call this function");_;
    }   

    // Mapping of user address to their loan details
    mapping(address => Loan) public loans;

    // Events
    event LoanCreated(
        address indexed user,
        uint256 btcCollateral,
        uint256 usdtLoan
    );
    event Liquidated(address indexed user, uint256 usdtLoan);
    event CollateralAdded(address indexed user, uint256 amount);
    event LoanRepaid(address indexed user, uint256 amount);
    event LoanIssued(
        address indexed user,
        uint256 btcCollateral,
        uint256 usdtLoan
    );

    // Function to liquidate a loan if collateral falls below threshold
    function liquidate(address _user, uint256 collateralValue) external {
        require(_user != address(0), "Invalid address");
        require(loans[_user].isActive, "Loan is not active");

        uint256 loanValue = loans[_user].usdtLoan;
        require(loanValue > 0, "No active loan to liquidate");

        // Check if liquidation threshold is breached
        // Using Solidity 0.8+ native calculations instead of SafeMath
        require(
            (collateralValue * 100) / loanValue < LIQUIDATION_THRESHOLD,
            "Liquidation threshold not reached"
        );
        this.loanRepayment(collateralValue);
        // Liquidate the loan
        loans[_user].isActive = false;

        emit Liquidated(_user, loanValue);
    }

    function updateBtcPrice(uint256 _btcPrice) external onlyOwner{

    }

    // Function to get loan details for a user
    function getLoanDetails(address _user)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
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

    // Dummy function to create a loan (for testing purposes)
    function createLoan(uint256 _btcCollateral, uint256 _usdtLoan) external {
        loans[msg.sender] = Loan({
            btcCollateral: _btcCollateral,
            usdtLoan: _usdtLoan,
            timestamp: block.timestamp,
            isActive: true
        });

        emit LoanCreated(msg.sender, _btcCollateral, _usdtLoan);
    }

    // Loan repayment
    function loanRepayment(uint256 _repaymentLoan) external {
        require(loans[msg.sender].isActive, "No Active loan");
        require(
            _repaymentLoan >= loans[msg.sender].usdtLoan,
            "Repayment amount insufficient"
        );
        require(
            usdt.transferFrom(msg.sender, address(this), _repaymentLoan),
            "USDT transfer failed"
        );
        require(
            wbtc.transferFrom(msg.sender, address(this), _repaymentLoan),
            "USDT transfer failed"
        );

        loans[msg.sender].isActive = false;
        emit LoanRepaid(msg.sender, _repaymentLoan);
    }

    function lockBtcAndGetLoan(uint256 _btcCollateral) external {
        require(_btcCollateral > 0, "BTC Collateral must be greater than 0");
        require(loans[msg.sender].isActive == false, "Loan already active");
        uint256 usdtLoanAmount = (((_btcCollateral * btcPrice) / 1e8) *
            LTV_RATIO) / 100;
        loans[msg.sender] = Loan({
            btcCollateral: _btcCollateral,
            usdtLoan: usdtLoanAmount,
            timestamp: block.timestamp,
            isActive: true
        });

        emit LoanIssued(msg.sender, _btcCollateral, usdtLoanAmount);
    }
}
