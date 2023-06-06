// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/IUsdc.sol";
import "./interfaces/IFactory.sol";
import "./BasicMetaTransaction.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

//TODO access control for buywithApproval

/**
 * @title istakpaza: paza contract
 * @notice this contract is used to mint and burn the paza token
 **/
contract Paza is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    BasicMetaTransaction,
    AccessControlUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    uint256 public constant MAX_CAP = 1000000 * 10**18;
    uint256 public constant PCT_BASE = 1000;

    uint256 constant price = 10**16;
    IERC20Upgradeable public usdc;
    IFactory public factory;
    event pazabuy(address user, uint256 _amount);
    event pazasell(address user, uint256 _amount);

    /**
     * @notice used to initialize the contract
     * @param _usdc address of usdc contract
     * @param _admin address to which  the  default admin role  will be given
     **/
    function initialize(address _usdc, address _admin) public initializer {
        __ERC20_init("xPAZA", "xPAZA");
        usdc = IERC20Upgradeable(_usdc);
        __AccessControl_init();
        __ERC20Burnable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    modifier validation(address _address) {
        require(_address != address(0), "zero address");
        _;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @notice used to set the usdc contarct
     * @param _usdc address of USDC contract
     **/

    function setUsdcContract(address _usdc)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validation(_usdc)
    {
        usdc = IERC20Upgradeable(_usdc);
    }

    /**
     * @notice used to give the Factory Role
     * @param _factory address of factory contract
     **/

    function setFactoryRole(address _factory)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validation(_factory)
    {
        _grantRole(FACTORY_ROLE, _factory);
    }

    /**
     * @notice used to buy the paza token by depositing the usdc
     * @param _amount amount of paza token to buy with PCT_BASE
     **/

    function buy(uint256 _amount) public {
        uint256 requiredUsdc = (_amount * 10**4) / PCT_BASE;
        require(
            usdc.balanceOf(_msgSender()) >= requiredUsdc,
            "Insufficient balance"
        );
        usdc.transferFrom(_msgSender(), address(this), requiredUsdc);
        _mint(_msgSender(), (_amount * 10**decimals()) / PCT_BASE);
        emit pazabuy(_msgSender(), (_amount * 10**decimals()) / PCT_BASE);
    }

    /**
     * @notice used to buy the paza token with approval
     * @param _payee address from which the  usdc will be transferred to _beneficiary
     * @param _beneficiary address that will receive the paza token
     * @param _amount of paza token usdc
     **/

    function buyWithApproval(
        address _payee,
        address _beneficiary,
        uint256 _amount
    ) external onlyRole(FACTORY_ROLE) {
        usdc.safeTransferFrom(_payee, address(this), _amount / 10**14);
        _mint(_beneficiary, _amount);
    }

    /**
     * @notice used to sell the paza token to get back the usdc
     * @param _amount of paza token to sell with PCT_BASE
     **/

    function sell(uint256 _amount) public {
        require(
            balanceOf(_msgSender()) >= (_amount * 10**decimals()) / PCT_BASE
        );
        _burn(_msgSender(), (_amount * 10**decimals()) / PCT_BASE);
        usdc.transfer(_msgSender(), (_amount * 10**4) / PCT_BASE);
        emit pazasell(_msgSender(), (_amount * 10**decimals()) / PCT_BASE);
    }

    /**
     * @notice used to get the token price
     * @return price of the paza token
     **/

    function getTokenPrice() public pure returns (uint256) {
        return price;
    }

    function _msgSender()
        internal
        view
        override(ContextUpgradeable, BasicMetaTransaction)
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