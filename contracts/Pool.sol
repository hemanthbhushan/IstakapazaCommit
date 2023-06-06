// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libraries/LoanLib.sol";
import "./interfaces/ILoanNFT.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPool.sol";
import "./BasicMetaTransaction.sol";




/** 
* @title istakpaza Pool contract
* @notice this contract used to update the borrower datails,
* calculate the claimable amount after any interval,
* implements the logic of stake and unstake 
**/

contract Pool is Initializable, BasicMetaTransaction, Ownable, AccessControl {
    using SafeERC20 for IERC20;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE"); 
    uint256 public constant TOTAL_TIME = 4 * 31104000; //YEAR IN SECONDS(360 days)

    IERC20 public paza;
    IFactory factory;

    mapping(address => mapping(uint256 => LoanLib.Loan)) public userDetail;
    mapping(address => mapping(uint256 => uint256)) public stakedAmount;
    mapping(address => mapping(uint256 => uint256)) public stakedTime;

    event ERC20TokensRemoved(
        address _tokenAddress,
        address sender,
        uint256 balance
    );

    event borrowerUnstaked(address _borrower, uint amount, uint amountStaked);

    modifier bankPoolStatus() {
        require(
            factory.isBankPoolBlacklisted(address(this)) != true,
            "Bank Blacklisted"
        );
        _;
    }

/** 
* @notice used to initialize the contract
* @param _owner address of owenr
* @param _token address of paza token
* @param _factory address of factory 
**/
function initialize(
        address _owner,
        address _token,
        address _factory
    ) public initializer {
        paza = IERC20(_token);
        _transferOwnership(_owner);
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _setupRole(OPERATOR_ROLE, _msgSender());
        factory = IFactory(_factory);
    }

/** 
* @notice used to update the user(borrower) details
* @param _details details of the borrower
* @param _loanId loanid of the  borrower 
**/
function updateUserDetail(LoanLib.Loan memory _details, uint256 _loanId)
        public
        bankPoolStatus
        onlyRole(OPERATOR_ROLE)
    {
        userDetail[_details.borrower][_loanId] = _details;
    }

/** 
* @notice used to calculatethe claimable amount 
* @param _borrower address of borrower 
* @param _loanId loan id of the borrower 
**/
function claimableAmount(address _borrower, uint256 _loanId)
        public
        view
        returns (uint256)
    {
        LoanLib.Loan memory temp = userDetail[_borrower][_loanId];
        if(temp.disbursementInterval == 0){
            return 0;
        }
        uint256 reward = temp.discount - stakedAmount[_borrower][_loanId];
        uint256 amtPerInterval = (reward * temp.disbursementInterval) /
            TOTAL_TIME;

        uint256 intervals = (block.timestamp - stakedTime[_borrower][_loanId]) /
            temp.disbursementInterval;

        return (amtPerInterval * intervals);
    }

/** 
* @notice used to update the staked amount of given loanId
* @param _user address of the user(borrower)
* @param _amount amount of paza token to be staked 
* @param _loanId loan id of the user(borrower)
**/
function stake(
        address _user,
        uint256 _amount,
        uint256 _loanId
    ) public bankPoolStatus onlyRole(OPERATOR_ROLE) {
        require(stakedAmount[_user][_loanId] == 0, "loan ID already exist");
        stakedAmount[_user][_loanId] = _amount;
        stakedTime[_user][_loanId] = block.timestamp;
    }


/** 
* @notice used for transfferring the staked amount from borower to bank
* @param _user address of borrower
* @param _loanId loan Id of the borrower  
**/

function transferStakedAmount(
        address _user,
        address _bank,
        uint256 _loanId
    ) external onlyRole(OPERATOR_ROLE) {
        
        paza.safeTransfer(_bank, stakedAmount[_user][_loanId]);
        
        stakedAmount[_user][_loanId] = 0;
    }


/** 
* @notice used for unstaking the  paza token for give loanID
* @param _borrower address of borrower 
* @param _loanId loan Id of the borrower  
**/
function unstake(address _borrower, uint256 _loanId) public bankPoolStatus {
        require(stakedAmount[_borrower][_loanId] > 0, "Invalid amount");

        require(
            block.timestamp >= stakedTime[_borrower][_loanId] + TOTAL_TIME,
            "Not time yet"
        );
        uint256 amount = claimableAmount(_borrower, _loanId);
        uint256 amountStaked = stakedAmount[_borrower][_loanId];
        stakedAmount[_borrower][_loanId] = 0;
        paza.safeTransfer(_borrower, amount + amountStaked);

        emit borrowerUnstaked( _borrower, amount, amountStaked);
    }

    function _msgSender()
        internal
        view
        override(Context, BasicMetaTransaction)
        returns (address sender)
    {
        if (msg.sender == address(this)) {
            bytes memory array = msg.data;
            uint256 index = msg.data.length;
            assembly {
                // Load the 32 bytes word from memory with the address on the lower 20 bytes, and mask those.
                sender := and(
                    mload(add(array, index)),
                    0xffffffffffffffffffffffffffffffffffffffff
                )
            }
        } else {
            return msg.sender;
        }
    }
}